import AppKit
import Foundation

@MainActor
enum RadialMenuClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType("com.gumu.codexmicro.radial-menu-item")

    static func copy(_ item: RadialMenuItem, to pasteboard: NSPasteboard = .general) throws {
        let data = try encodedData(for: item)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
    }

    static func item(from pasteboard: NSPasteboard = .general) -> RadialMenuItem? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return try? decodedItem(from: data)
    }

    nonisolated static func encodedData(for item: RadialMenuItem) throws -> Data {
        try JSONEncoder().encode(item)
    }

    nonisolated static func decodedItem(from data: Data) throws -> RadialMenuItem {
        try JSONDecoder().decode(RadialMenuItem.self, from: data)
    }
}
