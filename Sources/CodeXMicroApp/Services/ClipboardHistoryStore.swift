import AppKit
import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            isEnabled ? startMonitoring() : stopMonitoring()
        }
    }
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: Keys.retentionDays)
            pruneAndSave()
        }
    }

    static let retentionOptions = [1, 7, 30, 180, 365, 0]

    private enum Keys {
        static let enabled = "clipboardHistory.enabled"
        static let retentionDays = "clipboardHistory.retentionDays"
    }

    private let pasteboard: NSPasteboard
    private let fileURL: URL
    private var monitoringTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private let maximumItemCount = 100
    private let maximumImageBytes = 20 * 1_024 * 1_024

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = supportDirectory.appendingPathComponent("CodeXMicro", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("clipboard-history.json")
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
        self.retentionDays = UserDefaults.standard.object(forKey: Keys.retentionDays) as? Int ?? 7
        load()
        pruneAndSave()
    }

    deinit {
        monitoringTask?.cancel()
    }

    func startMonitoring() {
        guard isEnabled, monitoringTask == nil else { return }
        lastChangeCount = pasteboard.changeCount
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.capturePasteboardChangeIfNeeded()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func restore(_ item: ClipboardHistoryItem) -> Bool {
        guard item.write(to: pasteboard) else { return false }
        lastChangeCount = pasteboard.changeCount
        promote(item)
        return true
    }

    func delete(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func capturePasteboardChangeIfNeeded() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard let content = readContent() else { return }

        if items.first?.content == content { return }
        let application = NSWorkspace.shared.frontmostApplication
        let item = ClipboardHistoryItem(
            sourceApplicationName: application?.localizedName,
            sourceBundleIdentifier: application?.bundleIdentifier,
            content: content
        )
        items.insert(item, at: 0)
        pruneAndSave()
    }

    private func readContent() -> ClipboardHistoryItem.Content? {
        if let image = NSImage(pasteboard: pasteboard),
           let data = pngData(for: image),
           data.count <= maximumImageBytes {
            return .image(data)
        }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .text(text)
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private func promote(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index != 0 else { return }
        let existing = items.remove(at: index)
        items.insert(existing, at: 0)
        save()
    }

    private func pruneAndSave() {
        if retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
            items.removeAll { $0.createdAt < cutoff }
        }
        if items.count > maximumItemCount {
            items.removeLast(items.count - maximumItemCount)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Clipboard history is a convenience feature; a persistence failure
            // must not interrupt the app or modify the system pasteboard.
        }
    }
}
