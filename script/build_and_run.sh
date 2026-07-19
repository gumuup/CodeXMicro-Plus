#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodeXMicro++"
BUILD_PRODUCT="CodeXMicro"
PROCESS_PATTERN='CodeXMicro\+\+'
BUNDLE_ID="com.gumu.codexmicro.virtual"
VERSION="2.0.0"
BUILD_NUMBER="200"
MIN_SYSTEM_VERSION="14.0"
SIGNING_NAME="CodexMicro Local Development"
SIGNING_DIR="${CODEX_MICRO_SIGNING_DIR:-$HOME/Library/Application Support/CodexMicro/Signing}"
SIGNING_KEYCHAIN="$SIGNING_DIR/CodexMicroSigning-v1.keychain-db"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
LEGACY_APP_BUNDLE="$DIST_DIR/$BUILD_PRODUCT.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

"$ROOT_DIR/script/ensure_local_signing_identity.sh"
SIGNING_IDENTITY="$({ /usr/bin/security find-identity -p codesigning -v "$SIGNING_KEYCHAIN" || true; } | /usr/bin/awk -v name="$SIGNING_NAME" 'index($0, "\"" name "\"") { print $2; exit }')"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Unable to resolve signing identity: $SIGNING_NAME" >&2
  exit 1
fi

pkill -x "$PROCESS_PATTERN" >/dev/null 2>&1 || true
pkill -x 'CodexMicro\+\+' >/dev/null 2>&1 || true
pkill -x "$BUILD_PRODUCT" >/dev/null 2>&1 || true
pkill -x CodexMicro >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$BUILD_PRODUCT"

rm -rf "$APP_BUNDLE" "$LEGACY_APP_BUNDLE" "$DIST_DIR/CodexMicro++.app" "$DIST_DIR/CodexMicro.app"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/Sources/CodeXMicroApp/Resources/CodeXMicroHardware.png" ]]; then
  cp "$ROOT_DIR/Sources/CodeXMicroApp/Resources/CodeXMicroHardware.png" "$APP_RESOURCES/AppIcon.png"
fi

if [[ -f "$ROOT_DIR/Sources/CodeXMicroApp/Resources/CodexMarkReference.png" ]]; then
  cp "$ROOT_DIR/Sources/CodeXMicroApp/Resources/CodexMarkReference.png" "$APP_RESOURCES/CodexMarkReference.png"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>CodeXMicro++</string>
  <key>CFBundleDisplayName</key>
  <string>CodeXMicro++</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.png</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --keychain "$SIGNING_KEYCHAIN" \
  --identifier "$BUNDLE_ID" \
  "$APP_BUNDLE" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$PROCESS_PATTERN" >/dev/null
    echo "$APP_NAME is running from $APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
