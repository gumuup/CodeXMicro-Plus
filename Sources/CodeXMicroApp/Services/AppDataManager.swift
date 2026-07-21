import Combine
import Foundation

@MainActor
final class AppDataManager: ObservableObject {
    static let shared = AppDataManager()

    static let preferencesFilename = "CodeXMicroData.plist"
    static let iconsDirectoryName = "RadialIcons"

    @Published private(set) var dataDirectoryURL: URL

    private static let storagePathKey = "appDataStoragePath.v1"
    private static let managedPreferenceKeys = [
        "hapticStrength",
        "keySoundEnabled",
        "panelPosition",
        "seenTasks",
        "fastModeEnabled",
        "codexUsageMetric",
        "shortcutBindings.v1",
        "shortcutDefaultsVersion",
        "radialMenuItems.v1",
        "radialMenuProfiles.v1",
        "radialMenuGlobalModeEnabled"
    ]

    private var defaultsObserver: NSObjectProtocol?
    private init() {
        if let path = UserDefaults.standard.string(forKey: Self.storagePathKey), !path.isEmpty {
            dataDirectoryURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else {
            dataDirectoryURL = Self.defaultDataDirectory
        }
    }

    func prepareForLaunch() {
        do {
            try createDataDirectoryIfNeeded(at: dataDirectoryURL)
            let preferencesURL = preferencesURL(in: dataDirectoryURL)
            if FileManager.default.fileExists(atPath: preferencesURL.path) {
                let preferences = try readPreferences(from: dataDirectoryURL)
                applyToUserDefaults(preferences)
            }
        } catch {
            // Keep UserDefaults as the recovery source when the external store is unavailable.
        }
    }

    func startObservingUserDefaults() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? self?.saveCurrentPreferences()
            }
        }
        try? saveCurrentPreferences()
    }

    func saveCurrentPreferences() throws {
        try createDataDirectoryIfNeeded(at: dataDirectoryURL)
        let preferences = currentPreferences()
        let data = try PropertyListSerialization.data(
            fromPropertyList: preferences,
            format: .binary,
            options: 0
        )
        try data.write(to: preferencesURL(in: dataDirectoryURL), options: .atomic)
    }

    func overwriteData(at directory: URL) throws {
        let destination = try validatedDirectory(directory)
        try saveCurrentPreferences()

        if destination != dataDirectoryURL {
            try createDataDirectoryIfNeeded(at: destination)
            let sourceIcons = iconsURL(in: dataDirectoryURL)
            let destinationIcons = iconsURL(in: destination)
            if FileManager.default.fileExists(atPath: destinationIcons.path) {
                try FileManager.default.removeItem(at: destinationIcons)
            }
            if FileManager.default.fileExists(atPath: sourceIcons.path) {
                try FileManager.default.copyItem(at: sourceIcons, to: destinationIcons)
            }
        }

        dataDirectoryURL = destination
        UserDefaults.standard.set(destination.path, forKey: Self.storagePathKey)
        try saveCurrentPreferences()
    }

    func adoptData(at directory: URL) throws {
        let source = try validatedDirectory(directory)
        let preferences = try readPreferences(from: source)
        let report = try validate(preferences: preferences, directory: source)
        guard report.invalidPreferenceKeys.isEmpty else {
            throw DataError.integrityIssues(report.summary)
        }
        dataDirectoryURL = source
        UserDefaults.standard.set(source.path, forKey: Self.storagePathKey)
        applyToUserDefaults(preferences)
        try saveCurrentPreferences()
    }

    func createBackup(at destination: URL) throws {
        try saveCurrentPreferences()
        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodeXMicroBackup-\(UUID().uuidString)", isDirectory: true)
        let payload = stagingRoot.appendingPathComponent("CodeXMicroBackup", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: preferencesURL(in: dataDirectoryURL),
            to: payload.appendingPathComponent(Self.preferencesFilename)
        )
        let sourceIcons = iconsURL(in: dataDirectoryURL)
        if fileManager.fileExists(atPath: sourceIcons.path) {
            try fileManager.copyItem(
                at: sourceIcons,
                to: payload.appendingPathComponent(Self.iconsDirectoryName, isDirectory: true)
            )
        }

        let manifest: [String: Any] = [
            "formatVersion": 1,
            "createdAt": Date(),
            "application": "CodeXMicro++"
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: payload.appendingPathComponent("BackupManifest.plist"), options: .atomic)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", payload.path, destination.path])
    }

    func restoreBackup(from archive: URL) throws {
        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodeXMicroRestore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try runDitto(arguments: ["-x", "-k", archive.path, stagingRoot.path])

        let payload = stagingRoot.appendingPathComponent("CodeXMicroBackup", isDirectory: true)
        let preferences = try readPreferences(from: payload)
        let report = try validate(preferences: preferences, directory: payload)
        guard report.invalidPreferenceKeys.isEmpty else {
            throw DataError.integrityIssues(report.summary)
        }

        try createDataDirectoryIfNeeded(at: dataDirectoryURL)
        let destinationIcons = iconsURL(in: dataDirectoryURL)
        let restoredIcons = iconsURL(in: payload)
        if fileManager.fileExists(atPath: destinationIcons.path) {
            try fileManager.removeItem(at: destinationIcons)
        }
        if fileManager.fileExists(atPath: restoredIcons.path) {
            try fileManager.copyItem(at: restoredIcons, to: destinationIcons)
        }
        applyToUserDefaults(preferences)
        try saveCurrentPreferences()
    }

    func checkIntegrity() throws -> IntegrityReport {
        let preferences = try readPreferences(from: dataDirectoryURL)
        return try validate(preferences: preferences, directory: dataDirectoryURL)
    }

    func repairDataStore() throws -> IntegrityReport {
        var preferences = currentPreferences()
        for key in invalidKeys(in: preferences) {
            preferences.removeValue(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        repairMissingIconReferences(in: &preferences)
        try createDataDirectoryIfNeeded(at: dataDirectoryURL)
        let data = try PropertyListSerialization.data(
            fromPropertyList: preferences,
            format: .binary,
            options: 0
        )
        try data.write(to: preferencesURL(in: dataDirectoryURL), options: .atomic)
        return try validate(preferences: preferences, directory: dataDirectoryURL)
    }

    func rebuildDataStore() throws {
        for key in Self.managedPreferenceKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let iconDirectory = iconsURL(in: dataDirectoryURL)
        if FileManager.default.fileExists(atPath: iconDirectory.path) {
            try FileManager.default.removeItem(at: iconDirectory)
        }
        try saveCurrentPreferences()
    }

    func inspectRedundantData() throws -> CleanupReport {
        let referenced = referencedIconFilenames()
        let iconDirectory = iconsURL(in: dataDirectoryURL)
        guard FileManager.default.fileExists(atPath: iconDirectory.path) else {
            return CleanupReport(fileCount: 0, byteCount: 0)
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: iconDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let redundant = urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && !referenced.contains(url.lastPathComponent)
        }
        let bytes = redundant.reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
        return CleanupReport(fileCount: redundant.count, byteCount: bytes)
    }

    func cleanRedundantData() throws -> CleanupReport {
        let referenced = referencedIconFilenames()
        let iconDirectory = iconsURL(in: dataDirectoryURL)
        guard FileManager.default.fileExists(atPath: iconDirectory.path) else {
            return CleanupReport(fileCount: 0, byteCount: 0)
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: iconDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var removedCount = 0
        var removedBytes = Int64(0)
        for url in urls where !referenced.contains(url.lastPathComponent) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            removedBytes += Int64(values.fileSize ?? 0)
            try FileManager.default.removeItem(at: url)
            removedCount += 1
        }
        return CleanupReport(fileCount: removedCount, byteCount: removedBytes)
    }

    func iconsURL(in directory: URL? = nil) -> URL {
        (directory ?? dataDirectoryURL).appendingPathComponent(Self.iconsDirectoryName, isDirectory: true)
    }

    private static var defaultDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodeXMicro", isDirectory: true)
    }

    private func currentPreferences() -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Self.managedPreferenceKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                result[key] = value
            }
        }
        return result
    }

    private func applyToUserDefaults(_ preferences: [String: Any]) {
        for key in Self.managedPreferenceKeys {
            if let value = preferences[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private func readPreferences(from directory: URL) throws -> [String: Any] {
        let url = preferencesURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DataError.missingDataStore
        }
        let data = try Data(contentsOf: url)
        guard let preferences = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw DataError.invalidDataStore
        }
        return preferences
    }

    private func validate(preferences: [String: Any], directory: URL) throws -> IntegrityReport {
        let invalid = invalidKeys(in: preferences)
        let referencedIcons = referencedIconFilenames(in: preferences)
        let missingIcons = referencedIcons.filter {
            !FileManager.default.fileExists(atPath: iconsURL(in: directory).appendingPathComponent($0).path)
        }
        return IntegrityReport(invalidPreferenceKeys: invalid.sorted(), missingIconCount: missingIcons.count)
    }

    private func invalidKeys(in preferences: [String: Any]) -> [String] {
        var invalid: [String] = []
        func requireString(_ key: String) {
            if let value = preferences[key], !(value is String) { invalid.append(key) }
        }
        func requireNumber(_ key: String) {
            if let value = preferences[key], !(value is NSNumber) { invalid.append(key) }
        }
        requireString("hapticStrength")
        requireString("panelPosition")
        requireString("codexUsageMetric")
        requireNumber("keySoundEnabled")
        requireNumber("fastModeEnabled")
        requireNumber("shortcutDefaultsVersion")
        requireNumber("radialMenuGlobalModeEnabled")

        if let value = preferences["seenTasks"], !(value is [String: NSNumber]) && !(value is [String: Int64]) {
            invalid.append("seenTasks")
        }
        if let data = preferences["shortcutBindings.v1"] as? Data {
            if (try? JSONDecoder().decode([ShortcutTarget: KeyboardShortcutBinding].self, from: data)) == nil {
                invalid.append("shortcutBindings.v1")
            }
        } else if preferences["shortcutBindings.v1"] != nil {
            invalid.append("shortcutBindings.v1")
        }
        if let data = preferences["radialMenuProfiles.v1"] as? Data {
            if (try? JSONDecoder().decode([RadialMenuProfile].self, from: data)) == nil {
                invalid.append("radialMenuProfiles.v1")
            }
        } else if preferences["radialMenuProfiles.v1"] != nil {
            invalid.append("radialMenuProfiles.v1")
        }
        if let data = preferences["radialMenuItems.v1"] as? Data {
            if (try? JSONDecoder().decode([RadialMenuItem].self, from: data)) == nil {
                invalid.append("radialMenuItems.v1")
            }
        } else if preferences["radialMenuItems.v1"] != nil {
            invalid.append("radialMenuItems.v1")
        }
        return Array(Set(invalid))
    }

    private func referencedIconFilenames(in preferences: [String: Any]? = nil) -> Set<String> {
        let source = preferences ?? currentPreferences()
        var items: [RadialMenuItem] = []
        if let data = source["radialMenuProfiles.v1"] as? Data,
           let profiles = try? JSONDecoder().decode([RadialMenuProfile].self, from: data) {
            items += profiles.flatMap(\.presetCombinations).flatMap { $0 }
        }
        if let data = source["radialMenuItems.v1"] as? Data,
           let legacyItems = try? JSONDecoder().decode([RadialMenuItem].self, from: data) {
            items += legacyItems
        }
        return Set(items.compactMap { item in
            guard case let .local(filename) = RadialIconReference(rawValue: item.systemImage) else { return nil }
            let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
            return safeFilename == filename ? filename : nil
        })
    }

    private func repairMissingIconReferences(in preferences: inout [String: Any]) {
        let iconDirectory = iconsURL(in: dataDirectoryURL)

        func repairedItems(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
            items.map { item in
                var item = item
                if case let .local(filename) = RadialIconReference(rawValue: item.systemImage),
                   !FileManager.default.fileExists(
                       atPath: iconDirectory.appendingPathComponent(filename).path
                   ) {
                    item.systemImage = "photo"
                }
                return item
            }
        }

        if let data = preferences["radialMenuProfiles.v1"] as? Data,
           var profiles = try? JSONDecoder().decode([RadialMenuProfile].self, from: data) {
            for profileIndex in profiles.indices {
                for combinationIndex in profiles[profileIndex].presetCombinations.indices {
                    profiles[profileIndex].presetCombinations[combinationIndex] = repairedItems(
                        profiles[profileIndex].presetCombinations[combinationIndex]
                    )
                }
            }
            if let repaired = try? JSONEncoder().encode(profiles) {
                preferences["radialMenuProfiles.v1"] = repaired
                UserDefaults.standard.set(repaired, forKey: "radialMenuProfiles.v1")
            }
        }

        if let data = preferences["radialMenuItems.v1"] as? Data,
           let items = try? JSONDecoder().decode([RadialMenuItem].self, from: data),
           let repaired = try? JSONEncoder().encode(repairedItems(items)) {
            preferences["radialMenuItems.v1"] = repaired
            UserDefaults.standard.set(repaired, forKey: "radialMenuItems.v1")
        }
    }

    private func preferencesURL(in directory: URL) -> URL {
        directory.appendingPathComponent(Self.preferencesFilename)
    }

    private func createDataDirectoryIfNeeded(at directory: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw DataError.storageUnavailable }
            return
        }

        let parent = directory.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DataError.storageUnavailable
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: nil
        )
    }

    private func validatedDirectory(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL,
              standardized.path != "/",
              standardized != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL else {
            throw DataError.unsafeStorageLocation
        }
        return standardized
    }

    private func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DataError.archiveFailed(message ?? "ditto exited with status \(process.terminationStatus)")
        }
    }
}

struct IntegrityReport {
    let invalidPreferenceKeys: [String]
    let missingIconCount: Int

    var isHealthy: Bool { invalidPreferenceKeys.isEmpty && missingIconCount == 0 }

    var summary: String {
        if isHealthy { return "数据存储完整，未发现损坏。" }
        var parts: [String] = []
        if !invalidPreferenceKeys.isEmpty { parts.append("\(invalidPreferenceKeys.count) 项设置无效") }
        if missingIconCount > 0 { parts.append("\(missingIconCount) 个自定义图标缺失") }
        return "发现" + parts.joined(separator: "、") + "。"
    }
}

struct CleanupReport {
    let fileCount: Int
    let byteCount: Int64

    var summary: String {
        guard fileCount > 0 else { return "未发现可清理的冗余数据。" }
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        return "发现 \(fileCount) 个未使用的自定义素材，共 \(size)。"
    }
}

extension AppDataManager {
    enum DataError: LocalizedError {
        case missingDataStore
        case invalidDataStore
        case unsafeStorageLocation
        case storageUnavailable
        case integrityIssues(String)
        case archiveFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingDataStore:
                "所选位置不包含 CodeXMicroData.plist 数据文件。"
            case .invalidDataStore:
                "数据文件格式无效或已经损坏。"
            case .unsafeStorageLocation:
                "不能将磁盘根目录或用户主目录直接设为数据目录，请选择其下的专用文件夹。"
            case .storageUnavailable:
                "数据保存路径当前不可用，请确认磁盘已连接或重新选择路径。"
            case let .integrityIssues(message):
                "所选数据存在完整性问题：\(message)"
            case let .archiveFailed(message):
                "备份归档操作失败：\(message)"
            }
        }
    }
}
