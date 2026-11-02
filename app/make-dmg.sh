#!/bin/zsh
# Packs build/Sticky Note.app into build/Sticky.Note.dmg: open it, drag the note onto Applications.
# Usage: ./build.sh && ./make-dmg.sh
set -e
cd "$(dirname "$0")"
APP="build/Sticky Note.app"
[ -d "$APP" ] || { echo "No $APP yet; run ./build.sh first"; exit 1; }
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f build/Sticky.Note.dmg
hdiutil create -quiet -volname "Sticky Note" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/Sticky.Note.dmg
rm -rf "$STAGE"
echo "built: $PWD/build/Sticky.Note.dmg"
