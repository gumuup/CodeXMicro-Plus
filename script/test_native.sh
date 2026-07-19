#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BINARY="${TMPDIR:-/tmp}/codexmicro-native-parser-tests"
QUEUE_TEST_BINARY="${TMPDIR:-/tmp}/codexmicro-native-queue-tests"

cd "$ROOT_DIR"
xcrun swiftc \
  Sources/CodeXMicroApp/Models/CodexTask.swift \
  Sources/CodeXMicroApp/Models/WeeklyQuota.swift \
  Sources/CodeXMicroApp/Models/CodexUsageMetric.swift \
  Sources/CodeXMicroApp/Models/MicroAction.swift \
  Sources/CodeXMicroApp/Models/KeyboardShortcut.swift \
  Sources/CodeXMicroApp/Models/ToolboxAction.swift \
  Sources/CodeXMicroApp/Support/DialStepResolver.swift \
  Sources/CodeXMicroApp/Support/DialInteractionView.swift \
  Sources/CodeXMicroApp/Support/PanelResizeHandle.swift \
  Sources/CodeXMicroApp/Support/ProcessOutputReader.swift \
  Sources/CodeXMicroApp/Support/CodexRolloutParser.swift \
  tests/NativeParserTests/main.swift \
  -o "$TEST_BINARY"

"$TEST_BINARY"

xcrun swiftc \
  -parse-as-library \
  Sources/CodeXMicroApp/Support/SerialAsyncQueue.swift \
  tests/NativeQueueTests/main.swift \
  -o "$QUEUE_TEST_BINARY"

"$QUEUE_TEST_BINARY"
rm -f "$TEST_BINARY" "$QUEUE_TEST_BINARY"
