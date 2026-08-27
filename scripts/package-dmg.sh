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

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

sed \
  -e "s/__VERSION__/$VERSION/" \
  -e "s/__BUILD__/$BUILD_NUMBER/" \
  "$ROOT_DIR/Resources/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"

echo "==> Code signing"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "    using identity: $CODESIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "    CODESIGN_IDENTITY not set — ad-hoc signing (codesign --sign -)."
  echo "    This bundle will NOT pass Gatekeeper on other Macs. Set"
  echo "    CODESIGN_IDENTITY to a 'Developer ID Application: ...' identity"
  echo "    for a real distributable build."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Verifying signature"
codesign --verify --verbose "$APP_BUNDLE"

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
