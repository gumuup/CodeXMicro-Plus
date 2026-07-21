import AppKit
import Foundation

struct RadialCustomIconEntry: Identifiable, Hashable {
    let filename: String
    let url: URL

    var id: String { filename }
    var token: String { RadialIconReference.local(filename).rawValue }
    var image: NSImage? { NSImage(contentsOf: url) }
}

@MainActor
enum RadialCustomIconStore {
    static var directoryURL: URL {
        AppDataManager.shared.iconsURL()
    }

    static func entries() -> [RadialCustomIconEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { NSImage(contentsOf: $0) != nil }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .map { RadialCustomIconEntry(filename: $0.lastPathComponent, url: $0) }
    }

    static func importImage(from sourceURL: URL) throws -> RadialCustomIconEntry {
        guard NSImage(contentsOf: sourceURL) != nil else { throw ImportError.invalidImage }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let rawExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = rawExtension.isEmpty ? "png" : rawExtension
        let filename = UUID().uuidString.lowercased() + "." + fileExtension
        let destination = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return RadialCustomIconEntry(filename: filename, url: destination)
    }

    static func image(for reference: RadialIconReference) -> NSImage? {
        guard case let .local(filename) = reference else { return nil }
        let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
        guard safeFilename == filename else { return nil }
        return NSImage(contentsOf: directoryURL.appendingPathComponent(safeFilename))
    }

    enum ImportError: LocalizedError {
        case invalidImage

        var errorDescription: String? { "所选文件不是可读取的图片" }
    }
}
