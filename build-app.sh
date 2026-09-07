#!/bin/sh
# Builds LocalWhisper.app with SwiftPM (no Xcode project needed). Output: build/LocalWhisper.app
set -eu
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -vE "warning:|\^|^\s*[0-9]+ \||^\s*\|" || true

APP=build/LocalWhisper.app
pkill -x LocalWhisper 2>/dev/null || true   # a running app whose bundle is replaced fails TCC validation
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/LocalWhisper "$APP/Contents/MacOS/"
cp -R Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework "$APP/Contents/Frameworks/"
cp -c Resources/ggml-large-v3-turbo.bin "$APP/Contents/Resources/"   # APFS clone, instant
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/LocalWhisper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>nl.joris.localwhisper</string>
  <key>CFBundleName</key><string>LocalWhisper</string>
  <key>CFBundleExecutable</key><string>LocalWhisper</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>LocalWhisper records your voice while you hold the hotkey and transcribes it on this Mac.</string>
</dict></plist>
PLIST

# Sign with "LocalWhisper Dev" (see make-signing-cert.sh) so Accessibility grants survive rebuilds; ad-hoc otherwise.
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  if security find-identity -v -p codesigning | grep -q "LocalWhisper Dev"; then CODESIGN_IDENTITY="LocalWhisper Dev"; else CODESIGN_IDENTITY="-"; fi
fi
codesign --force --deep -s "$CODESIGN_IDENTITY" "$APP"
echo "signed with: $CODESIGN_IDENTITY"
codesign --verify --deep --strict "$APP" && echo "built $APP"
open "$APP"
