"""Regression fixtures for the binary deployment audit, independent of Apple tools."""

import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "Scripts/verify_deployment_targets.py"
SPEC = importlib.util.spec_from_file_location("deployment_audit", SCRIPT)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def macho(platform=2, minimum=16, cpu=0x100000C, install_name=None):
    """Build a minimal Mach-O with an actual deployment load command."""
    command = struct.pack("<IIIIII", 0x32, 24, platform, minimum << 16, 27 << 16, 0)
    count = 1
    if install_name:
        name = install_name.encode() + b"\0"
        name += b"\0" * ((-len(name)) % 8)
        command += struct.pack("<IIIIII", 0xD, 24 + len(name), 24, 0, 0, 0) + name
        count += 1
    return struct.pack("<IIIIIIII", 0xFEEDFACF, cpu, 0, 6, count, len(command), 0, 0) + command


def artifact_fixture(root):
    """Write tiny valid framework binaries, avoiding copies of shipped media libraries."""
    for name in audit.FRAMEWORKS:
        bundle = root / f"{name}.xcframework"
        libraries = []
        for (platform, variant), (platform_id, minimum) in audit.PLATFORMS.items():
            identifier = platform + ("-simulator" if variant else "-device")
            framework = bundle / identifier / f"{name}.framework"
            framework.mkdir(parents=True)
            (framework / name).write_bytes(macho(
                platform=platform_id,
                minimum=minimum[0],
                install_name=f"@rpath/{name}.framework/{name}",
            ))
            (framework / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": name,
                "MinimumOSVersion": str(minimum[0]),
            }))
            libraries.append({
                "LibraryIdentifier": identifier,
                "LibraryPath": f"{name}.framework",
                "BinaryPath": f"{name}.framework/{name}",
                "SupportedArchitectures": ["arm64"],
                "SupportedPlatform": platform,
                "SupportedPlatformVariant": variant,
            })
        (bundle / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))


class DeploymentAuditTests(unittest.TestCase):
    def test_thin_macho_reads_real_deployment_command(self):
        result = audit.parse_macho(macho())

        self.assertEqual(result["arm64"]["minimum"], (16, 0, 0))
        self.assertEqual(result["arm64"]["platform"], 2)

    def test_fat_macho_checks_both_architectures(self):
        first = macho(platform=7)
        second = macho(platform=7, minimum=18, cpu=0x1000007)
        offset = 48
        header = struct.pack(">II", 0xCAFEBABE, 2)
        header += struct.pack(">IIIII", 0x100000C, 0, offset, len(first), 0)
        header += struct.pack(">IIIII", 0x1000007, 0, offset + len(first), len(second), 0)

        result = audit.parse_macho(header + first + second)

        self.assertEqual(result["arm64"]["minimum"], (16, 0, 0))
        self.assertEqual(result["x86_64"]["minimum"], (18, 0, 0))

    def test_truncated_command_fails_with_actionable_error(self):
        with self.assertRaisesRegex(ValueError, "truncated"):
            audit.parse_macho(macho()[:-1])

    def test_wrong_binary_platform_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "platform"):
            audit.verify_slice(audit.parse_macho(macho(platform=3)), ["arm64"], 2, (16, 0, 0))

    def test_hidden_higher_floor_in_fat_architecture_is_rejected(self):
        result = audit.parse_macho(macho(minimum=18))

        with self.assertRaisesRegex(ValueError, "18.0.0.*16.0.0"):
            audit.verify_slice(result, ["arm64"], 2, (16, 0, 0))

    def test_missing_declared_architecture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "architectures"):
            audit.verify_slice(audit.parse_macho(macho()), ["arm64", "x86_64"], 2, (16, 0, 0))

    def test_framework_artifacts_with_matching_metadata_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact_fixture(root)

            frameworks, slices, architectures, symbols = audit.verify_artifacts(root)

            self.assertEqual((frameworks, slices, architectures, symbols), (9, 63, 63, 0))

    def test_framework_metadata_above_real_binary_floor_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact_fixture(root)
            plist = root / "AetherLibavcodec.xcframework/ios-device/AetherLibavcodec.framework/Info.plist"
            metadata = plistlib.loads(plist.read_bytes())
            metadata["MinimumOSVersion"] = "26.0"
            plist.write_bytes(plistlib.dumps(metadata))

            with self.assertRaisesRegex(ValueError, "MinimumOSVersion 26.0.0 differs from binary 16.0.0"):
                audit.verify_artifacts(root)

    def test_framework_with_unnamespaced_install_name_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact_fixture(root)
            binary = root / "AetherLibavcodec.xcframework/ios-device/AetherLibavcodec.framework/AetherLibavcodec"
            binary.write_bytes(macho(install_name="@rpath/Libavcodec.framework/Libavcodec"))

            with self.assertRaisesRegex(ValueError, "invalid Aether install name"):
                audit.verify_artifacts(root)


if __name__ == "__main__":
    unittest.main()
