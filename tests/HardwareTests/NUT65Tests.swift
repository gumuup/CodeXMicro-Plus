import Foundation
import Testing
@testable import CodeXMicroApp

@Test func nut65PacketAndBigEndianKeycode() throws {
    let command = try NUT65Protocol.keyCommand(write: 0x0806, layer: 2, row: 3, column: 4)
    #expect(command == [5, 2, 3, 4, 8, 6])
    let packet = try NUT65Protocol.packet(command)
    #expect(packet.count == 64)
    #expect(Array(packet.prefix(6)) == command)
    #expect(packet.dropFirst(6).allSatisfy { $0 == 0 })
    #expect(try NUT65Protocol.decode([0x7c, 0x16, 0x52, 0x21, 0x00, 0xe3]) == [0x7c16, 0x5221, 0x00e3])
    #expect(throws: NUT65Error.self) { try NUT65Protocol.decode([0x7c]) }
    #expect(throws: NUT65Error.self) { try NUT65Protocol.keyCommand(layer: -1, row: 0, column: 0) }
    #expect(throws: NUT65Error.self) { try NUT65Protocol.keyCommand(layer: 0, row: 6, column: 0) }
    #expect(throws: NUT65Error.self) { try NUT65Protocol.packet([1], size: 16) }
}

@Test func nut65PhysicalLayoutAndUnknownKeysArePreserved() throws {
    #expect(NUT65Layout.keys.count == 67)
    #expect(Set(NUT65Layout.keys.map(\.id)).count == NUT65Layout.keys.count)
    #expect(NUT65Layout.keys.allSatisfy { (0..<90).contains($0.id) })
    #expect(NUT65Layout.keys.first { $0.label == "Enter" }?.id == 43)
    #expect(NUT65Layout.keys.first { $0.label == "Space" }?.id == 65)
    #expect(NUT65Layout.keys.first { $0.label == "FN" }?.id == 71)
    #expect(NUT65Keycodes.title(0x0806) == "⌘C")
    #expect(NUT65Keycodes.title(0x5223) == "Fn → 层 3")
    #expect(NUT65Keycodes.title(0xffff) == "0xFFFF")
    let snapshot = NUT65Snapshot(capturedAt: Date(), vendorID: 13357, productID: 58650, locationID: 1,
                                 version: 12, layers: [Array(repeating: 0xffff, count: 90)])
    try snapshot.validate()
    let decoded = try JSONDecoder().decode(NUT65Snapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(decoded.layers == snapshot.layers)
    let malformed = NUT65Snapshot(capturedAt: Date(), vendorID: 13357, productID: 58650, locationID: 1,
                                  version: 12, layers: [[0]])
    #expect(throws: NUT65Error.self) { try malformed.validate() }
}

@Test func nut65MacEditorDoesNotDefaultToWindowsLayer() {
    #expect(NUT65Layers.initialLayer(saved: nil, count: 5) == 2)
    #expect(NUT65Layers.initialLayer(saved: 0, count: 5) == 0)
    #expect(NUT65Layers.initialLayer(saved: 3, count: 5) == 3)
    #expect(NUT65Layers.initialLayer(saved: 99, count: 5) == 2)
    #expect(NUT65Layers.initialLayer(saved: 2, count: 1) == 0)
    #expect(NUT65Layers.title(2, count: 5) == "层 2 · Mac")
    #expect(NUT65Layers.title(0, count: 5) == "层 0 · Win")
}
