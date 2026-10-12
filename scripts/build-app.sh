#!/bin/bash
# Builds OneBuds in release mode and packages build/OneBuds.app (bundle id com.local.onebuds),
# signed with the stable local identity so the Bluetooth permission survives rebuilds.
#
#   scripts/build-app.sh             build only
#   scripts/build-app.sh --install   also copy to /Applications (replacing an older copy) and open it
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/signing-common.sh"

app="$root/build/OneBuds.app"
bundle_id="com.local.onebuds"
install=false
[[ "${1:-}" == "--install" ]] && install=true

cd "$root"
swift build -c release --product OneBuds
binary="$(swift build -c release --show-bin-path)/OneBuds"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/OneBuds"
# Drop local symbols: about half the size. (Crash reports then show fewer symbol names.)
strip -x "$app/Contents/MacOS/OneBuds"
cp "$root/Packaging/OneBuds-Info.plist" "$app/Contents/Info.plist"
[[ -f "$root/Packaging/AppIcon.icns" ]] && cp "$root/Packaging/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# Licensed per-model artwork for the connection card (<profile-id>.usdz / .png / .heic), if any.
for asset in "$root"/Packaging/EarbudAssets/*.usdz "$root"/Packaging/EarbudAssets/*.png "$root"/Packaging/EarbudAssets/*.heic; do
  [[ -f "$asset" ]] || continue
  mkdir -p "$app/Contents/Resources/EarbudAssets"
  cp "$asset" "$app/Contents/Resources/EarbudAssets/"
done
plutil -lint "$app/Contents/Info.plist" >/dev/null

onebuds_sign "$app" "$bundle_id"
echo "Built $app"

if $install; then
  destination="/Applications/OneBuds.app"
  [[ -w /Applications ]] || destination="$HOME/Applications/OneBuds.app"
  mkdir -p "$(dirname "$destination")"
  pkill -x OneBuds 2>/dev/null || true
  rm -rf "$destination"
  cp -R "$app" "$destination"
  echo "Installed $destination"
  open "$destination"
fi
