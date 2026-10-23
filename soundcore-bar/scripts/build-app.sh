#!/bin/zsh
# Builds build/SoundcoreBar.app with the openscq30 CLI embedded next to the main executable.
# The CLI inherits the app's Bluetooth permission (NSBluetoothAlwaysUsageDescription in Info.plist).
set -euo pipefail

root=${0:A:h:h}
cli=${OPENSCQ30_BIN:-$root/../target/release-fast/openscq30}
app=$root/build/SoundcoreBar.app

[[ -x $cli ]] || { echo "openscq30 CLI not found at $cli (set OPENSCQ30_BIN)" >&2; exit 1; }

swift build --package-path "$root" -c release
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$(swift build --package-path "$root" -c release --show-bin-path)/SoundcoreBar" "$app/Contents/MacOS/"
cp "$cli" "$app/Contents/MacOS/openscq30"
# Optional product renders for the connected popup; the app falls back to an SF Symbol without them.
mkdir -p "$app/Contents/Resources"
for image in DeviceLeft DeviceRight; do
  [[ -f $root/Resources/$image.png ]] && cp "$root/Resources/$image.png" "$app/Contents/Resources/"
done
codesign --force --sign - "$app/Contents/MacOS/openscq30"
codesign --force --sign - "$app"
echo "$app"
