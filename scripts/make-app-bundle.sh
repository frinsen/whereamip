#!/bin/bash
# Assemble WhereAmIP.app from the SPM release build.
# Usage: scripts/make-app-bundle.sh [output-dir]   (default: ./dist)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
# Scoped to the whereamipVersion line specifically — Version.swift also
# declares welcomeMilestone (another quoted dotted-number literal), which a
# file-wide grep would pick up too and corrupt VERSION into a multi-line value.
VERSION=$(grep '^public let whereamipVersion' Sources/WhereAmIPCore/Version.swift | grep -o '"[0-9][0-9.]*"' | tr -d '"')
# SWIFT_BUILD_FLAGS lets callers (e.g. the Homebrew formula, which already ran
# its own `swift build -c release --disable-sandbox`) pass extra flags into
# this script's build so it doesn't spawn a second, differently-sandboxed
# `swift build` invocation. Empty by default for local/CI usage.
swift build -c release ${SWIFT_BUILD_FLAGS:-}
APP="$OUT/WhereAmIP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WhereAmIPApp "$APP/Contents/MacOS/whereamip"
# SPM resource bundles go into Contents/Resources/ (proper macOS bundle
# structure); codesign rejects loose .bundle dirs sitting in Contents/MacOS/
# next to the executable. Bundle.main.resourceURL (the resolvers' first
# candidate) resolves to Contents/Resources/ when launched as a .app.
for bundle in .build/release/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# Two icon paths, both committed artifacts built by scripts/update-appicon.sh
# (never compiled here — actool needs full Xcode, and this script must keep
# working under Homebrew's CLT-only build environment):
#   - AppIcon.icns: legacy CFBundleIconFile path, still read by older subsystems.
#   - Assets.car: compiled asset catalog, CFBundleIconName path — required by
#     newer subsystems (notably notification banners) that don't fall back
#     to CFBundleIconFile/.icns at all. Both keys are set below deliberately
#     (belt and suspenders), not just the newer one.
cp docs/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp docs/Assets.car "$APP/Contents/Resources/Assets.car"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WhereAmIP</string>
  <key>CFBundleDisplayName</key><string>WhereAmIP</string>
  <key>CFBundleIdentifier</key><string>io.github.frinsen.whereamip</string>
  <key>CFBundleExecutable</key><string>whereamip</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <!-- The UI strings live in the nested SPM resource bundle's en.lproj/de.lproj, NOT in
       Contents/Resources/*.lproj, so macOS cannot infer this app's languages by looking at
       the app bundle: without this key it treats WhereAmIP as English-only, which both hides
       it from System Settings > Language & Region > Applications (the per-app language
       picker) and risks the app's effective AppleLanguages list being narrowed to English
       before the nested bundle is ever consulted. Declaring them explicitly is the
       documented way to say what a bundle can speak. Keep this list in step with the
       .lproj folders under Sources/WhereAmIPUI/Resources — L10nTests.shippedLocales is the
       same list on the test side. -->
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
  <key>NSAppTransportSecurity</key><dict>
    <key>NSExceptionDomains</key><dict>
      <key>api.ipify.org</key><dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
      </dict>
    </dict>
  </dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP"   # ad-hoc signature (local identity; fine for build-from-source)
echo "Built $APP (v$VERSION)"
