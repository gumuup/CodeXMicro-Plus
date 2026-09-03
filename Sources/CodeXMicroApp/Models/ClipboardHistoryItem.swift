import AppKit
import Foundation

struct ClipboardHistoryItem: Identifiable, Codable, Equatable, Sendable {
    enum Content: Codable, Equatable, Sendable {
        case text(String)
        case image(Data)
    }

    let id: UUID
    let createdAt: Date
    let sourceApplicationName: String?
    let sourceBundleIdentifier: String?
    let content: Content

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?,
        content: Content
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.content = content
    }

    var searchableText: String {
        switch content {
        case let .text(value):
            [value, sourceApplicationName].compactMap { $0 }.joined(separator: " ")
        case .image:
            ["图片", sourceApplicationName].compactMap { $0 }.joined(separator: " ")
        }
    }

    @MainActor
    func write(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        switch content {
        case let .text(value):
            return pasteboard.setString(value, forType: .string)
        case let .image(data):
            guard let image = NSImage(data: data) else { return false }
            return pasteboard.writeObjects([image])
        }
    }
}
