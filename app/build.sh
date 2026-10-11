#!/bin/zsh
# Builds Sticky Note.app into ./build. Usage: ./build.sh
set -e
cd "$(dirname "$0")"
APP="build/Sticky Note.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Universal binary: runs on Apple Silicon and Intel Macs
SRC=(StickyNote.swift Note.swift TaskText.swift Decor.swift)
TMP=$(mktemp -d)
for arch in arm64 x86_64; do swiftc -O -parse-as-library -target $arch-apple-macosx15.0 -o "$TMP/$arch" "${SRC[@]}"; done
lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$APP/Contents/MacOS/StickyNote"
rm -rf "$TMP"
cp Resources/*.ttf Resources/OFL.txt Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>Sticky Note</string>
  <key>CFBundleName</key><string>Sticky Note</string>
  <key>CFBundleExecutable</key><string>StickyNote</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.aakanksha.stickynote.scrapbook</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built: $PWD/$APP"
