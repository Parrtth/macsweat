#!/bin/zsh
# Builds build/MacSweat.app as a universal app (Apple silicon + Intel).
#   ./build.sh            build only
#   ./build.sh --install  also copy it to /Applications and open it
set -eu
cd "${0:A:h}"
name=MacSweat
bundle_id=dev.parthh.macsweat
version=$(<VERSION)
build_number=$(git rev-list --count HEAD 2>/dev/null || print 1)
app="$PWD/build/$name.app"
cache=/private/tmp/macsweat-module-cache
mkdir -p build Resources
touch build/.metadata_never_index # keep build copies out of Spotlight; the installed app is the one to open

# Regenerate the icon whenever its drawing code changes.
if [[ ! -f Resources/AppIcon.icns || Tools/make-icon.swift -nt Resources/AppIcon.icns ]]; then
  iconset="$(mktemp -d)/AppIcon.iconset"
  xcrun swiftc -O -module-cache-path $cache Tools/make-icon.swift -o build/make-icon
  build/make-icon "$iconset" Resources/AppIcon-1024.png
  iconutil -c icns "$iconset" -o Resources/AppIcon.icns
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -O -module-cache-path $cache -target $arch-apple-macos13.0 \
    -framework AppKit -framework SwiftUI -framework ServiceManagement \
    Sources/*.swift -o "build/$name-$arch"
done
lipo -create "build/$name-arm64" "build/$name-x86_64" -output "$app/Contents/MacOS/$name"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleDisplayName</key><string>$name</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>MIT License · macsweat.parthh.dev</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app ($version, $(lipo -archs "$app/Contents/MacOS/$name"))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x $name 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/$name.app"
  ditto "$app" "/Applications/$name.app"
  open "/Applications/$name.app"
  print "Installed and opened: /Applications/$name.app"
fi
