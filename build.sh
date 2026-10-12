#!/usr/bin/env bash
# Builds the SwiftPM package and wraps it into "Copilot Credits.app".
#   ./build.sh           -> build/Copilot Credits.app
#   ./build.sh install   -> also copies it to /Applications and launches it
#   ./build.sh dmg       -> also produces build/CopilotCredits.dmg (drag and drop)
#
# Optional variables (used by CI):
#   VERSION=0.2.0     displayed version (CFBundleShortVersionString)
#   BUILD_NUMBER=42   build number (CFBundleVersion)
#   UNIVERSAL=1       universal binary, Apple Silicon + Intel
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Copilot Credits"
EXEC="CopilotCredits"
APP="build/${APP_NAME}.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ swift build (release${UNIVERSAL:+, universal})"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "▸ Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PLIST"
fi

# Ad hoc signature: enough for the Keychain and notifications,
# but not for Gatekeeper on a downloaded app (see README).
echo "▸ Ad hoc signing"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "install" ]]; then
    echo "▸ Installing to /Applications"
    pkill -x "$EXEC" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    open "/Applications/${APP_NAME}.app"
fi

if [[ "${1:-}" == "dmg" ]]; then
    # Classic disk image: the app + a shortcut to /Applications.
    DMG="build/CopilotCredits.dmg"
    STAGE="build/dmg"
    echo "▸ Creating ${DMG}"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "✓ ${DMG}"
fi

echo "✓ ${APP}"
