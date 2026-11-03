#!/bin/bash
# Packages build/OneBuds.app (made by scripts/build-app.sh) as build/OneBuds-<version>.dmg, with an
# Applications shortcut so it installs by drag and drop.
#
#   scripts/make-dmg.sh 0.2.0
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?usage: scripts/make-dmg.sh <version>}"
app="$root/build/OneBuds.app"
dmg="$root/build/OneBuds-$version.dmg"
[[ -d "$app" ]] || { echo "Missing $app; run scripts/build-app.sh first." >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "OneBuds $version" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"
echo "Built $dmg"
