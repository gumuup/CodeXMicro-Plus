#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodeXMicro++"
BUILD_PRODUCT="CodeXMicro"
DISPLAY_NAME="CodeXMicro++"
BUNDLE_ID="com.gumu.codexmicro.virtual"
VERSION="${CODEX_MICRO_VERSION:-1.1.1}"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/distribution"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
STAGING_DIR="$BUILD_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-universal.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGING_DIR" "$DIST_DIR"

build_arch() {
  local arch="$1"
  local scratch="$BUILD_DIR/$arch"
  swift build \
    --package-path "$ROOT_DIR" \
    --configuration release \
    --arch "$arch" \
    --scratch-path "$scratch" >&2
  find "$scratch" -type f -path "*/release/$BUILD_PRODUCT" -perm -111 -print -quit
}

ARM_BINARY="$(build_arch arm64)"
INTEL_BINARY="$(build_arch x86_64)"
if [[ -z "$ARM_BINARY" || -z "$INTEL_BINARY" ]]; then
  echo "Unable to locate one or more release binaries" >&2
  exit 1
fi

/usr/bin/lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Sources/CodeXMicroApp/Resources/CodeXMicroHardware.png" "$RESOURCES_DIR/AppIcon.png"
cp "$ROOT_DIR/Sources/CodeXMicroApp/Resources/CodexMarkReference.png" "$RESOURCES_DIR/CodexMarkReference.png"

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>CodeXMicro++</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon.png</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$APP_BUNDLE"
if [[ -n "${CODEX_MICRO_DEVELOPER_ID:-}" ]]; then
  /usr/bin/codesign --force --deep --options runtime --timestamp \
    --sign "$CODEX_MICRO_DEVELOPER_ID" "$APP_BUNDLE"
  SIGNING_DESCRIPTION="$CODEX_MICRO_DEVELOPER_ID"
else
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
  SIGNING_DESCRIPTION="ad-hoc（未公证）"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/应用程序 Applications"
cp "$ROOT_DIR/安装说明.txt" "$STAGING_DIR/安装说明.txt"
cp "$ROOT_DIR/LICENSE" "$STAGING_DIR/LICENSE"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
/usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")"
) > "$CHECKSUM_PATH"

echo "Created: $DMG_PATH"
echo "Signing: $SIGNING_DESCRIPTION"
/usr/bin/file "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cat "$CHECKSUM_PATH"
