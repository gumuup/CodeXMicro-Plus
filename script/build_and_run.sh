#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodeXMicro++"
BUILD_PRODUCT="CodeXMicro"
PROCESS_PATTERN='CodeXMicro\+\+'
BUNDLE_ID="com.gumu.codexmicro.virtual"
VERSION="3.0.0"
BUILD_NUMBER="300"
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
for _ in {1..20}; do
  if ! pgrep -x "$PROCESS_PATTERN" >/dev/null 2>&1 \
      && ! pgrep -x "$BUILD_PRODUCT" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

cd "$ROOT_DIR"
if swift build; then
  BUILD_BINARY="$(swift build --show-bin-path)/$BUILD_PRODUCT"
else
  DIRECT_SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
  DIRECT_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
  DIRECT_BUILD_DIR="$ROOT_DIR/.build/direct"
  DIRECT_MODULE_CACHE="$DIRECT_BUILD_DIR/module-cache"
  case "$(uname -m)" in
    arm64) DIRECT_TARGET="arm64-apple-macosx$MIN_SYSTEM_VERSION" ;;
    x86_64) DIRECT_TARGET="x86_64-apple-macosx$MIN_SYSTEM_VERSION" ;;
    *) echo "Unsupported build architecture: $(uname -m)" >&2; exit 1 ;;
  esac

  if [[ ! -x "$DIRECT_SWIFTC" || ! -d "$DIRECT_SDK" ]]; then
    echo "swift build failed and the direct Xcode toolchain is unavailable" >&2
    exit 1
  fi

  echo "swift build unavailable; falling back to the Xcode Swift toolchain"
  mkdir -p "$DIRECT_BUILD_DIR" "$DIRECT_MODULE_CACHE"
  SWIFT_SOURCES=()
  while IFS= read -r source; do
    SWIFT_SOURCES+=("$source")
  done < <(/usr/bin/find "$ROOT_DIR/Sources/CodeXMicroApp" -name '*.swift' -type f -print | /usr/bin/sort)

  BUILD_BINARY="$DIRECT_BUILD_DIR/$BUILD_PRODUCT"
  "$DIRECT_SWIFTC" \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -parse-as-library \
    -sdk "$DIRECT_SDK" \
    -target "$DIRECT_TARGET" \
    -module-cache-path "$DIRECT_MODULE_CACHE" \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_BINARY"
fi

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

LAUNCHED_PID=""
open_app() {
  # Launch this exact build. LaunchServices may otherwise reopen an older
  # /Applications copy that has the same bundle identifier.
  /usr/bin/nohup "$APP_BINARY" >/dev/null 2>&1 &
  LAUNCHED_PID="$!"
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
    sleep 3
    if [[ -z "$LAUNCHED_PID" ]] || ! kill -0 "$LAUNCHED_PID" >/dev/null 2>&1; then
      echo "$APP_NAME failed to stay running from $APP_BUNDLE" >&2
      exit 1
    fi
    BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
    if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
      echo "Expected version $VERSION, found $BUILT_VERSION" >&2
      exit 1
    fi
    echo "$APP_NAME is running from $APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
