#!/bin/zsh
# Downscale AppIcon-1024.png into the macOS icon sizes referenced by AppIcon.appiconset/Contents.json
# and copy a 256 px version into Docs/images. Uses only macOS `sips`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SET="$ROOT/Constellate/Assets.xcassets/AppIcon.appiconset"
SRC="$SET/AppIcon-1024.png"
[[ -s "$SRC" ]] || { echo "missing $SRC (run render_assets.py --icon-only first)"; exit 1; }
for s in 16 32 64 128 256 512 1024; do
  /usr/bin/sips -s format png -z $s $s "$SRC" --out "$SET/icon_$s.png" >/dev/null
done
mkdir -p "$ROOT/Docs/images"
cp "$SET/icon_256.png" "$ROOT/Docs/images/icon-256.png"
ls -la "$SET"
