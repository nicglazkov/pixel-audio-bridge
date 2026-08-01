#!/bin/bash
# Build PixelAudioBridge.app — SwiftUI menu bar + window app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/PixelAudioBridge.app"
CONTENTS="$APP/Contents"
TARGET="arm64-apple-macosx14.0"

mkdir -p "$BUILD"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# ---------------------------------------------------------------------- icon
echo "generating icon…"
swiftc -O -target "$TARGET" -o "$BUILD/icongen" "$ROOT/app/IconGen.swift" -framework AppKit
rm -rf "$BUILD/AppIcon.iconset"
"$BUILD/icongen" "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

# ------------------------------------------------------------------ Info.plist
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Pixel Audio Bridge</string>
    <key>CFBundleDisplayName</key>       <string>Pixel Audio Bridge</string>
    <key>CFBundleExecutable</key>        <string>PixelAudioBridge</string>
    <key>CFBundleIdentifier</key>        <string>com.glazkov.pixel-audio-bridge</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleVersion</key>           <string>1.1</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# ----------------------------------------------------------------- compile app
# IconGen.swift is deliberately excluded: it is a standalone tool with top-level
# code, which cannot coexist with the @main entry point.
echo "compiling app…"
swiftc -O -target "$TARGET" \
    -o "$CONTENTS/MacOS/PixelAudioBridge" \
    "$ROOT/app/BridgeController.swift" \
    "$ROOT/app/ContentView.swift" \
    "$ROOT/app/PixelAudioBridgeApp.swift"

# paboutput reads and sets the default output device. It is the safety mechanism
# now that scrcpy plays directly and cannot be pinned to a device, so pab refuses
# to run guarded without it.
echo "compiling paboutput…"
swiftc -O -target "$TARGET" -o "$BUILD/paboutput" "$ROOT/app/OutputDevice.swift" -framework CoreAudio

# Ship the bridge script and its helper side by side; pab resolves paboutput
# relative to its own location.
cp "$ROOT/bin/pab"        "$CONTENTS/Resources/pab"
cp "$BUILD/paboutput"     "$CONTENTS/Resources/paboutput"
chmod +x "$CONTENTS/Resources/pab" "$CONTENTS/Resources/paboutput"

# Ad-hoc signature: macOS may refuse to launch an unsigned bundle.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"

# Nudge Finder/Dock to pick up a changed icon rather than serving a cached one.
touch "$APP"

echo "built: $APP"
