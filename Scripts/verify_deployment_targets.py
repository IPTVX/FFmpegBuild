#!/usr/bin/env python3
"""Audit shipped XCFrameworks using plist and Mach-O data, without Apple tools."""

import argparse
from pathlib import Path
import plistlib
import struct
import sys


FRAMEWORKS = {
    "AetherLibavcodec", "AetherLibavformat", "AetherLibavutil",
    "AetherLibswresample", "AetherLibswscale", "AetherLibavfilter",
    "AetherLibdav1d", "AetherLibzimg", "AetherLibzvbi",
}
PLATFORMS = {
    ("ios", ""): (2, (16, 0, 0)),
    ("ios", "simulator"): (7, (16, 0, 0)),
    ("tvos", ""): (3, (16, 0, 0)),
    ("tvos", "simulator"): (8, (16, 0, 0)),
    ("macos", ""): (1, (14, 0, 0)),
    ("xros", ""): (11, (1, 0, 0)),
    ("xros", "simulator"): (12, (1, 0, 0)),
}
ARCHITECTURES = {0x100000C: "arm64", 0x1000007: "x86_64"}


def version(value):
    """Normalize dotted plist versions and packed Mach-O versions."""
    if isinstance(value, int):
        return value >> 16, (value >> 8) & 255, value & 255
    parts = tuple(int(part) for part in value.split("."))
    return (parts + (0, 0, 0))[:3]


def describe(value):
    return ".".join(str(part) for part in value)


def parse_macho(data):
    """Read every architecture's deployment, UUID and dylib load commands."""
    if len(data) < 8:
        raise ValueError("truncated Mach-O header")
    fat = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
           b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    if data[:4] in fat:
        endian, wide = fat[data[:4]]
        count = struct.unpack_from(endian + "I", data, 4)[0]
        size = 32 if wide else 20
        if len(data) < 8 + count * size:
            raise ValueError("truncated universal architecture table")
        result = {}
        for index in range(count):
            offset = 8 + index * size
            cpu = struct.unpack_from(endian + "I", data, offset)[0]
            start, length = struct.unpack_from(endian + ("QQ" if wide else "II"), data, offset + 8)
            if start + length > len(data):
                raise ValueError("truncated universal architecture payload")
            child = parse_macho(data[start:start + length])
            if set(child) != {ARCHITECTURES.get(cpu)} or set(child) & set(result):
                raise ValueError("universal architecture table does not match payload")
            result.update(child)
        return result
    thin = {b"\xcf\xfa\xed\xfe": ("<", 32), b"\xfe\xed\xfa\xcf": (">", 32),
            b"\xce\xfa\xed\xfe": ("<", 28), b"\xfe\xed\xfa\xce": (">", 28)}
    if data[:4] not in thin:
        raise ValueError("expected a thin or universal Mach-O binary")
    endian, offset = thin[data[:4]]
    if len(data) < offset:
        raise ValueError("truncated Mach-O header")
    cpu = struct.unpack_from(endian + "I", data, 4)[0]
    if cpu not in ARCHITECTURES:
        raise ValueError(f"unexpected CPU type {cpu:#x}")
    count, command_bytes = struct.unpack_from(endian + "II", data, 16)
    end = offset + command_bytes
    if end > len(data):
        raise ValueError("truncated Mach-O load commands")
    record = {"dependencies": [], "install_name": None, "uuid": None}
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("truncated Mach-O load command")
        command, size = struct.unpack_from(endian + "II", data, offset)
        if size < 8 or offset + size > end:
            raise ValueError("truncated or invalid Mach-O load command")
        if command == 0x32:
            if size < 24:
                raise ValueError("truncated LC_BUILD_VERSION")
            platform, minimum = struct.unpack_from(endian + "II", data, offset + 8)
            record.update(platform=platform, minimum=version(minimum))
        elif command == 0x1B:
            if size < 24:
                raise ValueError("truncated LC_UUID")
            record["uuid"] = data[offset + 8:offset + 24].hex()
        elif command in (0xD, 0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023):
            if size < 24:
                raise ValueError("truncated dylib command")
            start = struct.unpack_from(endian + "I", data, offset + 8)[0]
            if start < 24 or start >= size:
                raise ValueError("invalid dylib name offset")
            raw_name = data[offset + start:offset + size]
            if b"\0" not in raw_name:
                raise ValueError("unterminated dylib name")
            name = raw_name.split(b"\0", 1)[0].decode("utf-8")
            if command == 0xD:
                record["install_name"] = name
            else:
                record["dependencies"].append(name)
        offset += size
    if offset != end:
        raise ValueError("load command count does not match declared size")
    if "minimum" not in record:
        raise ValueError("missing LC_BUILD_VERSION deployment information")
    return {ARCHITECTURES[cpu]: record}


def verify_slice(records, architectures, platform, maximum):
    """Reject missing slices, mismatched platforms and raised deployment floors."""
    if set(records) != set(architectures):
        raise ValueError(f"architectures {sorted(records)} differ from metadata {sorted(architectures)}")
    for architecture, record in records.items():
        if record["platform"] != platform:
            raise ValueError(f"{architecture}: binary platform {record['platform']} differs from {platform}")
        if record["minimum"] > maximum:
            raise ValueError(f"{architecture}: binary minimum {describe(record['minimum'])} exceeds {describe(maximum)}")


def verify_artifacts(sources):
    """Audit distributed frameworks and their advertised debug-symbol bundles."""
    bundles = {path.stem: path for path in sources.glob("*.xcframework")}
    if set(bundles) != FRAMEWORKS:
        raise ValueError(f"expected nine Aether frameworks; missing={sorted(FRAMEWORKS - set(bundles))}, unexpected={sorted(set(bundles) - FRAMEWORKS)}")
    forbidden = [str(path) for path in sources.rglob("*")
                 if "dtsx" in path.name.lower() and path.suffix in (".framework", ".xcframework")]
    if forbidden:
        raise ValueError(f"removed DTSX framework is still distributed: {forbidden}")
    slices = architectures = symbols = 0
    for name, bundle in sorted(bundles.items()):
        metadata = plistlib.loads((bundle / "Info.plist").read_bytes())
        seen = set()
        for library in metadata["AvailableLibraries"]:
            identifier = library["LibraryIdentifier"]
            try:
                key = library["SupportedPlatform"], library.get("SupportedPlatformVariant", "")
                if key not in PLATFORMS or key in seen:
                    raise ValueError(f"unsupported or duplicate platform {key}")
                seen.add(key)
                platform, maximum = PLATFORMS[key]
                root = bundle / identifier
                framework = root / library["LibraryPath"]
                binary = root / library["BinaryPath"]
                records = parse_macho(binary.read_bytes())
                verify_slice(records, library["SupportedArchitectures"], platform, maximum)
                plist_path = framework / "Info.plist"
                if not plist_path.exists():
                    plist_path = framework / "Versions/A/Resources/Info.plist"
                info = plistlib.loads(plist_path.read_bytes())
                declared = version(info["MinimumOSVersion"])
                actual = max(record["minimum"] for record in records.values())
                if declared != actual:
                    raise ValueError(f"framework MinimumOSVersion {describe(declared)} differs from binary {describe(actual)}")
                if info["CFBundleExecutable"] != name:
                    raise ValueError("CFBundleExecutable does not match framework name")
                for architecture, record in records.items():
                    install = record["install_name"] or ""
                    if not install.startswith(f"@rpath/{name}.framework/") or Path(install).name != name:
                        raise ValueError(f"{architecture}: invalid Aether install name {install}")
                    for dependency in record["dependencies"]:
                        if "dtsx" in dependency.lower() or (dependency.startswith("@") and not dependency.startswith("@rpath/Aether")):
                            raise ValueError(f"{architecture}: unnamespaced or removed dependency {dependency}")
                if "DebugSymbolsPath" in library:
                    dwarf = root / library["DebugSymbolsPath"] / f"{name}.framework.dSYM/Contents/Resources/DWARF/{name}"
                    debug = parse_macho(dwarf.read_bytes())
                    verify_slice(debug, library["SupportedArchitectures"], platform, maximum)
                    for architecture in records:
                        if not records[architecture]["uuid"] or records[architecture]["uuid"] != debug[architecture]["uuid"]:
                            raise ValueError(f"{architecture}: dSYM UUID differs from distributed binary")
                    symbols += len(debug)
                slices += 1
                architectures += len(records)
            except (KeyError, ValueError, OSError, struct.error) as error:
                raise ValueError(f"{name}/{identifier}: {error}") from error
        if seen != set(PLATFORMS):
            raise ValueError(f"{name}: missing platform slices {set(PLATFORMS) - seen}")
    return len(bundles), slices, architectures, symbols


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=Path(__file__).resolve().parents[1] / "Sources")
    arguments = parser.parse_args()
    try:
        frameworks, slices, architectures, symbols = verify_artifacts(arguments.sources)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"PASS: {frameworks} frameworks, {slices} slices, {architectures} Mach-O architectures, {symbols} matching dSYM architectures; deployment floors iOS/tvOS 16, macOS 14, visionOS 1; Aether install names; no DTSX framework.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
