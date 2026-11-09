#!/bin/bash
# Execute through a FlowDeck aggregate target. The fixture stays outside the repository.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="${1:?Pass an official FATE DTS/DTS-HD sample path}"
package="${2:-$root}"
output="$(mktemp -d "${TMPDIR:-/tmp}/dts-compatibility.XXXXXX")"
trap 'rm -rf "$output"' EXIT
flags=()
for framework in "$package"/Sources/*.xcframework; do
    name="$(basename "$framework" .xcframework)"
    dir="$framework/macos-arm64_x86_64"
    flags+=(-F "$dir" -Wl,-rpath,"$dir" -framework "$name")
done
xcrun --sdk macosx clang -target arm64-apple-macos14.0 \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    "$root/Tests/DecoderFixtures/DTSHeightsCompatibility.c" "${flags[@]}" \
    -o "$output/validate"
"$output/validate" "$fixture"
