#!/bin/zsh
# Builds build/Mac Pulse.app.  ./build.sh --install also copies it to /Applications and opens it.
set -eu
cd "${0:A:h}"
app="$PWD/build/Mac Pulse.app"
cache=/private/tmp/mac-pulse-module-cache
mkdir -p build Resources
touch build/.metadata_never_index # keep the build copy out of Spotlight; the installed app is the one to open

if [[ ! -f Resources/AppIcon.icns ]]; then
  iconset="$(mktemp -d)/AppIcon.iconset"
  xcrun swiftc -O -module-cache-path $cache Tools/make-icon.swift -o build/make-icon
  build/make-icon "$iconset"
  iconutil -c icns "$iconset" -o Resources/AppIcon.icns
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -O -module-cache-path $cache -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  Sources/*.swift -o "$app/Contents/MacOS/MacPulse"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacPulse</string>
<key>CFBundleIdentifier</key><string>local.parth.mac-pulse</string>
<key>CFBundleName</key><string>Mac Pulse</string>
<key>CFBundleDisplayName</key><string>Mac Pulse</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MacPulse 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/Mac Pulse.app"
  ditto "$app" "/Applications/Mac Pulse.app"
  open "/Applications/Mac Pulse.app"
  print "Installed and opened: /Applications/Mac Pulse.app"
fi
