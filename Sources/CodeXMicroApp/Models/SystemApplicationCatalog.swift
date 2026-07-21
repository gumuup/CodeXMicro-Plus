import Foundation

struct SystemApplicationOption: Identifiable, Hashable, Sendable {
    let path: String
    let name: String

    var id: String { path }
}

enum SystemApplicationCatalog {
    static let applications: [SystemApplicationOption] = discoverApplications()

    private static func discoverApplications() -> [SystemApplicationOption] {
        let fileManager = FileManager.default
        let roots = [
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
        ]
        let additionalPaths = [
            "/System/Library/CoreServices/Finder.app",
        ]

        var paths = Set(additionalPaths.filter { fileManager.fileExists(atPath: $0) })
        for root in roots {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: root, isDirectory: true),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            paths.formUnion(urls.filter { $0.pathExtension.lowercased() == "app" }.map(\.path))
        }

        let preferredOrder = [
            "System Settings.app",
            "App Store.app",
            "Activity Monitor.app",
            "Terminal.app",
            "Disk Utility.app",
            "Console.app",
            "Screenshot.app",
            "Finder.app",
        ]
        let order = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($1, $0) })

        return paths.map { path in
            SystemApplicationOption(
                path: path,
                name: fileManager.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            )
        }
        .sorted { lhs, rhs in
            let lhsFilename = URL(fileURLWithPath: lhs.path).lastPathComponent
            let rhsFilename = URL(fileURLWithPath: rhs.path).lastPathComponent
            let lhsOrder = order[lhsFilename] ?? Int.max
            let rhsOrder = order[rhsFilename] ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
