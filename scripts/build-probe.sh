#!/bin/bash
# Builds onebuds-probe in release mode and packages it as "build/OneBuds Probe.app"
# (bundle id com.local.onebuds.probe) so macOS asks for Bluetooth permission for the probe itself.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/signing-common.sh"

app="$root/build/OneBuds Probe.app"
bundle_id="com.local.onebuds.probe"

cd "$root"
swift build -c release --product onebuds-probe
binary="$(swift build -c release --show-bin-path)/onebuds-probe"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/onebuds-probe"
cp "$root/Packaging/OneBudsProbe-Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

onebuds_sign "$app" "$bundle_id"
echo "Built $app"
