#!/bin/bash
# Build PixelAudioBridge.app.
#
#   ./build.sh                 ad hoc signature, for local use
#   SIGN=developer ./build.sh  Developer ID, hardened runtime, secure timestamp
#
# The release path exists because notarization has three hard requirements: a
# Developer ID signature, hardened runtime, and a secure timestamp. Ad hoc
# signing satisfies none of them, and an ad hoc hash changes every build, which
# also means macOS treats each rebuild as a different app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/PixelAudioBridge.app"
CONTENTS="$APP/Contents"

VERSION="1.3.0"
MIN_MACOS="14.0"
DEVELOPER_ID="Developer ID Application: Nicholas Glazkov (M7D6YHVDNK)"

# Universal by default. Apple silicon and Intel are both claimed in the docs, so
# both have to actually be in the binary.
ARCHS=(arm64 x86_64)

mkdir -p "$BUILD"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Compile one source set for every architecture and lipo the slices together.
build_universal() {
  local out="$1"; shift
  local slices=()
  for arch in "${ARCHS[@]}"; do
    local slice="$BUILD/.$(basename "$out").$arch"
    swiftc -O -target "$arch-apple-macosx$MIN_MACOS" -o "$slice" "$@"
    slices+=("$slice")
  done
  lipo -create -output "$out" "${slices[@]}"
  rm -f "${slices[@]}"
}

# ---------------------------------------------------------------------- icon
# A build-time tool, never shipped, so it only needs to run on this machine.
echo "generating icon"
swiftc -O -o "$BUILD/icongen" "$ROOT/app/IconGen.swift" -framework AppKit
rm -rf "$BUILD/AppIcon.iconset"
"$BUILD/icongen" "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

# ------------------------------------------------------------------ Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Pixel Audio Bridge</string>
    <key>CFBundleDisplayName</key>       <string>Pixel Audio Bridge</string>
    <key>CFBundleExecutable</key>        <string>PixelAudioBridge</string>
    <key>CFBundleIdentifier</key>        <string>com.glazkov.pixel-audio-bridge</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>MIT licensed. Copyright (c) 2026 Nic Glazkov.</string>
</dict>
</plist>
PLIST

# --------------------------------------------------------------------- binaries
# IconGen.swift is excluded deliberately: it is a standalone tool with top level
# code, which cannot coexist with the @main entry point.
echo "compiling app (${ARCHS[*]})"
build_universal "$CONTENTS/MacOS/PixelAudioBridge" \
    "$ROOT/app/BridgeController.swift" \
    "$ROOT/app/UpdateChecker.swift" \
    "$ROOT/app/ContentView.swift" \
    "$ROOT/app/PixelAudioBridgeApp.swift"

echo "compiling paboutput (${ARCHS[*]})"
build_universal "$CONTENTS/MacOS/paboutput" "$ROOT/app/OutputDevice.swift"

# The Mach-O helper belongs in MacOS, where codesign expects executables. The
# shell script stays in Resources: codesign demands a signature for anything in
# MacOS, and a script's signature lives in an extended attribute, which does not
# reliably survive archiving.
cp "$ROOT/bin/pab" "$CONTENTS/Resources/pab"
chmod +x "$CONTENTS/Resources/pab" "$CONTENTS/MacOS/paboutput"

# ----------------------------------------------------------------------- sign
if [ "${SIGN:-adhoc}" = "developer" ]; then
  echo "signing with Developer ID"
  # Inner code first, then the bundle. --deep is discouraged by Apple and signs
  # nested code with the outer options whether or not that is correct.
  for target in "$CONTENTS/MacOS/paboutput" "$APP"; do
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID" "$target"
  done
  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
else
  echo "signing ad hoc (local use only)"
  codesign --force --sign - "$CONTENTS/MacOS/paboutput" >/dev/null 2>&1 || true
  codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  warning: ad hoc codesign failed"
fi

touch "$APP"   # nudge Finder to re-read a changed icon rather than serve a cached one

echo "built: $APP"
lipo -archs "$CONTENTS/MacOS/PixelAudioBridge" | sed 's/^/  architectures: /'
