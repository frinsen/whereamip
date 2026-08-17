#!/bin/bash
# Regenerate docs/AppIcon.icns and docs/Assets.car from docs/icon-source.svg —
# the single source of truth for both.
#
# Two icon paths exist because macOS reads app icons two different ways:
#   - CFBundleIconFile -> AppIcon.icns (legacy, still read by older subsystems)
#   - CFBundleIconName -> compiled asset catalog (Assets.car) — required by
#     newer subsystems (notably notification banners) that don't fall back
#     to the .icns at all.
# Compiling an asset catalog needs `actool`, which ships only with full
# Xcode, not the Command Line Tools — but `brew install` must keep working
# with CLT alone. So Assets.car is built ONCE here, at dev time, and
# committed to docs/; scripts/make-app-bundle.sh (which brew's formula runs)
# only ever COPIES the committed file, never compiles it.
#
# Usage: scripts/update-appicon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="docs/icon-source.svg"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

XCODE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if [ ! -d "$XCODE_DEVELOPER_DIR" ]; then
  echo "This script needs full Xcode (for actool), not just the Command Line" >&2
  echo "Tools — install Xcode from the App Store / developer.apple.com and retry." >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Render each size directly from the vector source (never by downsampling
# one big raster) so small sizes stay crisp — qlmanage's SVG thumbnailer
# re-rasterizes fresh at whatever size you ask for, same as the pipeline
# AppIcon.icns was originally built with (see e29765f: "icns rendered
# per-size from vector for crisp small sizes").
for size in 16 32 64 128 256 512 1024; do
  out="$WORK/render-$size"
  mkdir -p "$out"
  qlmanage -t -s "$size" -o "$out" "$SRC" >/dev/null 2>&1
  produced="$out/$(basename "$SRC").png"
  [ -f "$produced" ] || { echo "qlmanage produced no thumbnail at size $size" >&2; exit 1; }
  # qlmanage's requested size is a hint (fits within a bounding box), not a
  # hard guarantee — force the exact square dimension every consumer
  # (iconset/appiconset) requires. In practice it already lands exact, but
  # this makes that a guarantee rather than an assumption.
  sips -z "$size" "$size" "$produced" --out "$WORK/icon_$size.png" >/dev/null
done

# --- .icns (legacy path — CFBundleIconFile) ---
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$WORK/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$WORK/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$WORK/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$WORK/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$WORK/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$WORK/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$WORK/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$WORK/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$WORK/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$WORK/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns -o docs/AppIcon.icns "$ICONSET"
echo "Wrote docs/AppIcon.icns"

# --- Assets.car (modern path — CFBundleIconName) ---
XCASSETS="$WORK/AppIcon.xcassets"
APPICONSET="$XCASSETS/AppIcon.appiconset"
mkdir -p "$APPICONSET"
cp "$ICONSET/icon_16x16.png"      "$APPICONSET/icon_16x16.png"
cp "$ICONSET/icon_16x16@2x.png"   "$APPICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_32x32.png"      "$APPICONSET/icon_32x32.png"
cp "$ICONSET/icon_32x32@2x.png"   "$APPICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_128x128.png"    "$APPICONSET/icon_128x128.png"
cp "$ICONSET/icon_128x128@2x.png" "$APPICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_256x256.png"    "$APPICONSET/icon_256x256.png"
cp "$ICONSET/icon_256x256@2x.png" "$APPICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_512x512.png"    "$APPICONSET/icon_512x512.png"
cp "$ICONSET/icon_512x512@2x.png" "$APPICONSET/icon_512x512@2x.png"

cat > "$APPICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
cat > "$XCASSETS/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

COMPILED="$WORK/compiled"
mkdir -p "$COMPILED"
env DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun actool \
  --output-format human-readable-text --notices --warnings \
  --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$WORK/partial.plist" \
  --compile "$COMPILED" \
  "$XCASSETS"

[ -f "$COMPILED/Assets.car" ] || { echo "actool did not produce Assets.car" >&2; exit 1; }
cp "$COMPILED/Assets.car" docs/Assets.car
echo "Wrote docs/Assets.car"
