#!/usr/bin/env bash
set -euo pipefail

# package-dmg.sh — builds EarlySync in release config, assembles a minimal
# .app bundle, code-signs it, and packages it into a distributable DMG.
#
# Code signing and notarization are optional and env-driven, so this script
# runs end-to-end in CI or locally even without real Apple Developer
# credentials:
#   - CODESIGN_IDENTITY unset -> ad-hoc sign (codesign --sign -). Fine for
#     local testing; Gatekeeper will still block the result on other Macs.
#   - CODESIGN_IDENTITY set   -> signs with that identity, e.g.
#     "Developer ID Application: Your Name (TEAMID)".
#   - APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID all set -> notarizes via
#     `xcrun notarytool submit`; otherwise notarization is skipped with a
#     warning (the DMG will show an "unidentified developer" prompt).

APP_NAME="EarlySync"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Building $APP_NAME $VERSION (release)"
swift build -c release --package-path "$ROOT_DIR"

echo "==> Assembling app bundle at $APP_BUNDLE"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$BUILD_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Default to empty, not the literal placeholder text — UpdaterService.swift
# treats a non-empty SUPublicEDKey as "a real key is configured" and would
# try to initialize Sparkle with garbage if the placeholder were left in.
sed \
  -e "s/__VERSION__/$VERSION/" \
  -e "s/__BUILD__/$BUILD_NUMBER/" \
  -e "s/__SPARKLE_PUBLIC_ED_KEY__/${SPARKLE_PUBLIC_ED_KEY:-}/" \
  "$ROOT_DIR/Resources/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"

sign() {
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$1"
  else
    codesign --force --sign - "$1"
  fi
}

echo "==> Code signing"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "    using identity: $CODESIGN_IDENTITY"
else
  echo "    CODESIGN_IDENTITY not set — ad-hoc signing (codesign --sign -)."
  echo "    This bundle will NOT pass Gatekeeper on other Macs. Set"
  echo "    CODESIGN_IDENTITY to a 'Developer ID Application: ...' identity"
  echo "    for a real distributable build."
fi

# Sparkle.framework bundles its own nested helper app and XPC services.
# --deep on the outer app is unreliable for structures this nested — sign
# from the innermost component out, per Sparkle's own distribution guidance.
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
sign "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
sign "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose "$APP_BUNDLE"

echo "==> Creating DMG at $DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo "==> Notarizing"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$DMG_PATH"
else
  echo "==> Skipping notarization (APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID not all set)."
  echo "    Gatekeeper will show an 'unidentified developer' warning on other Macs."
fi

echo "==> Done: $DMG_PATH"
