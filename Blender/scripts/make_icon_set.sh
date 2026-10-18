#!/bin/zsh
# Downscale the Blender-rendered macOS tile (mac_1024.png) into the sizes referenced by
# AppIcon.appiconset/Contents.json, remove the legacy icon_*.png set, and copy a 256 px version of the
# iOS icon into Docs/images. Uses only macOS `sips`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SET="$ROOT/Constellate/Assets.xcassets/AppIcon.appiconset"
MAC="$SET/mac_1024.png"
IOS="$SET/AppIcon-1024.png"
[[ -s "$MAC" && -s "$IOS" ]] || { echo "missing $MAC or $IOS (run render_icons.py first)"; exit 1; }
for s in 16 32 64 128 256 512; do
  /usr/bin/sips -s format png -z $s $s "$MAC" --out "$SET/mac_$s.png" >/dev/null
done
rm -f "$SET"/icon_*.png
mkdir -p "$ROOT/Docs/images"
/usr/bin/sips -s format png -z 256 256 "$IOS" --out "$ROOT/Docs/images/icon-256.png" >/dev/null
ls -la "$SET"
