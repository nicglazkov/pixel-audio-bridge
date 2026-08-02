#!/bin/bash
# Build, sign, package, notarize, staple and verify a release.
#
#   ./release.sh
#
# Produces dist/PixelAudioBridge-<version>.dmg and .zip, both notarized and
# stapled, plus the sha256 the Homebrew cask needs.
#
# Order matters in two places. Notarization runs on the DMG, and stapling has to
# happen after it, because a rebuild or repackage discards the ticket. A zip
# cannot be stapled at all, so the app is stapled first and zipped afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/PixelAudioBridge.app"
DIST="$ROOT/dist"
PROFILE="notary"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "")"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Building with Developer ID"
SIGN=developer "$ROOT/build.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# Deliberately unversioned. releases/latest/download/<asset> only resolves if the
# asset name is stable, and that URL is what the website links to.
DMG="$DIST/PixelAudioBridge.dmg"
ZIP="$DIST/PixelAudioBridge.zip"
echo "version $VERSION"

step "Checking the signature notarization will require"
# Captured once rather than piped into `grep -q`: with pipefail, grep exiting
# early on a match sends SIGPIPE to codesign, and the pipeline then reports
# failure even though the check passed.
SIGINFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
ENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null || true)"
printf '%s\n' "$SIGINFO" | grep -E "^Authority=Developer ID|^Timestamp=|^CodeDirectory" | sed 's/^/  /'

case "$SIGINFO" in
  *"flags=0x10000(runtime)"*) echo "  hardened runtime: present" ;;
  *) echo "  hardened runtime: MISSING, notarization will fail"; exit 1 ;;
esac
case "$ENTS" in
  *get-task-allow*) echo "  get-task-allow: PRESENT, notarization will fail"; exit 1 ;;
  *) echo "  get-task-allow: absent" ;;
esac
case "$SIGINFO" in
  *"Authority=Developer ID Application"*) echo "  authority: Developer ID" ;;
  *) echo "  authority: NOT Developer ID, notarization will fail"; exit 1 ;;
esac
lipo -archs "$APP/Contents/MacOS/PixelAudioBridge" | sed 's/^/  architectures: /'

step "Building the DMG"
rm -rf "$DIST" "$ROOT/build/dmgroot"
mkdir -p "$DIST" "$ROOT/build/dmgroot"
cp -R "$APP" "$ROOT/build/dmgroot/"
create-dmg \
  --volname "Pixel Audio Bridge" \
  --window-pos 200 120 --window-size 560 380 \
  --icon-size 110 \
  --icon "PixelAudioBridge.app" 150 175 \
  --app-drop-link 410 175 \
  --hide-extension "PixelAudioBridge.app" \
  --no-internet-enable \
  "$DMG" "$ROOT/build/dmgroot/" >/dev/null
rm -rf "$ROOT/build/dmgroot"
echo "  $(basename "$DMG"), $(du -h "$DMG" | cut -f1)"

step "Notarizing (typically 2 to 15 minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | sed 's/^/  /'

step "Stapling"
# Both. The app inside a stapled DMG is not itself stapled.
xcrun stapler staple "$DMG" 2>&1 | sed 's/^/  dmg: /'
xcrun stapler staple "$APP" 2>&1 | sed 's/^/  app: /'

step "Zipping the stapled app"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "  $(basename "$ZIP"), $(du -h "$ZIP" | cut -f1)"

step "Verifying the way a stranger's Mac will"
spctl -a -vvv -t install "$APP" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$DMG" 2>&1 | sed 's/^/  /'

step "Checksums for the Homebrew cask"
shasum -a 256 "$DMG" | sed 's/^/  /'
shasum -a 256 "$ZIP" | sed 's/^/  /'
