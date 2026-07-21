#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BINARY="${TMPDIR:-/tmp}/codexmicro-native-parser-tests"
QUEUE_TEST_BINARY="${TMPDIR:-/tmp}/codexmicro-native-queue-tests"
DIRECT_SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
DIRECT_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if [[ -x "$DIRECT_SWIFTC" && -d "$DIRECT_SDK" ]]; then
  case "$(uname -m)" in
    arm64) DIRECT_TARGET="arm64-apple-macosx14.0" ;;
    x86_64) DIRECT_TARGET="x86_64-apple-macosx14.0" ;;
    *) echo "Unsupported test architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  SWIFTC=("$DIRECT_SWIFTC" -sdk "$DIRECT_SDK" -target "$DIRECT_TARGET")
else
  SWIFTC=(xcrun swiftc)
fi

cd "$ROOT_DIR"
"${SWIFTC[@]}" \
  Sources/CodeXMicroApp/Models/CodexTask.swift \
  Sources/CodeXMicroApp/Models/WeeklyQuota.swift \
  Sources/CodeXMicroApp/Models/CodexUsageMetric.swift \
  Sources/CodeXMicroApp/Models/MicroAction.swift \
  Sources/CodeXMicroApp/Models/KeyboardShortcut.swift \
  Sources/CodeXMicroApp/Models/ToolboxAction.swift \
  Sources/CodeXMicroApp/Models/RadialIcon.swift \
  Sources/CodeXMicroApp/Models/RadialMenuItem.swift \
  Sources/CodeXMicroApp/Models/SystemApplicationCatalog.swift \
  Sources/CodeXMicroApp/Services/RadialMenuClipboard.swift \
  Sources/CodeXMicroApp/Support/DialStepResolver.swift \
  Sources/CodeXMicroApp/Support/DialInteractionView.swift \
  Sources/CodeXMicroApp/Support/CodexKeybindingResolver.swift \
  Sources/CodeXMicroApp/Support/PanelResizeHandle.swift \
  Sources/CodeXMicroApp/Support/PointerPanelPlacement.swift \
  Sources/CodeXMicroApp/Support/ProcessOutputReader.swift \
  Sources/CodeXMicroApp/Support/CodexRolloutParser.swift \
  tests/NativeParserTests/main.swift \
  -o "$TEST_BINARY"

"$TEST_BINARY"

"${SWIFTC[@]}" \
  -parse-as-library \
  Sources/CodeXMicroApp/Support/SerialAsyncQueue.swift \
  tests/NativeQueueTests/main.swift \
  -o "$QUEUE_TEST_BINARY"

"$QUEUE_TEST_BINARY"
rm -f "$TEST_BINARY" "$QUEUE_TEST_BINARY"
