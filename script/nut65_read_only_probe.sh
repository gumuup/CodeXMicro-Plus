#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nut65-probe.XXXXXX")"
cat > "$PROBE_DIR/main.swift" <<'SWIFT'
import Foundation
do {
    let connection = try NUT65Connection()
    let snapshot = try connection.readSnapshot()
    var checked = 0
    for layer in snapshot.layers.indices {
        for key in NUT65Layout.keys {
            let value = try connection.readKey(layer: layer, row: key.row, column: key.column)
            guard value == snapshot.layers[layer][key.id] else {
                throw NUT65Error.message("批量／单键读取不一致：层 \(layer)，键 \(key.label)")
            }
            checked += 1
        }
    }
    print("READ ONLY VERIFIED: protocol=\(snapshot.version), layers=\(snapshot.layers.count), matrix=6x15, physicalKeys=\(NUT65Layout.keys.count), comparisons=\(checked)")
} catch {
    print("READ FAILED: \(error.localizedDescription)")
    exit(1)
}
SWIFT
swiftc -swift-version 6 \
    "$ROOT_DIR/Sources/CodeXMicroApp/Hardware/NUT65Protocol.swift" \
    "$ROOT_DIR/Sources/CodeXMicroApp/Hardware/NUT65Connection.swift" \
    "$ROOT_DIR/Sources/CodeXMicroApp/Hardware/NUT65Layout.swift" \
    "$PROBE_DIR/main.swift" -o "$PROBE_DIR/read"
"$PROBE_DIR/read"
