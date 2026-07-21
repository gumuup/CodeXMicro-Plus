import Foundation

enum RadialMenuAction: Codable, Hashable, Sendable {
    case unconfigured
    case codexToolbox(ToolboxAction)
    case keyboardShortcut(KeyboardShortcutBinding)
    case application(path: String)
    case systemApplication(path: String)
    case plugin(identifier: String)
    case website(url: String)
    case pasteText(String)
    case folder(path: String)
    case shortcut(name: String)

    var kind: RadialMenuActionKind {
        switch self {
        case .unconfigured: .unconfigured
        case .codexToolbox: .codexToolbox
        case .keyboardShortcut: .keyboardShortcut
        case .application: .application
        case .systemApplication: .systemApplication
        case .plugin: .plugin
        case .website: .website
        case .pasteText: .pasteText
        case .folder: .folder
        case .shortcut: .shortcut
        }
    }

    var summary: String {
        switch self {
        case .unconfigured: "待配置"
        case let .codexToolbox(action): action.title
        case let .keyboardShortcut(binding): binding.displayName
        case let .application(path): URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case let .systemApplication(path): URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case let .plugin(identifier): RadialPluginPreset(rawValue: identifier)?.title ?? identifier
        case let .website(url): url
        case let .pasteText(text): text.isEmpty ? "尚未填写文本" : text
        case let .folder(path): URL(fileURLWithPath: path).lastPathComponent
        case let .shortcut(name): name
        }
    }

    static func defaultAction(for kind: RadialMenuActionKind) -> RadialMenuAction {
        switch kind {
        case .unconfigured: .unconfigured
        case .codexToolbox: .codexToolbox(.openCodex)
        case .keyboardShortcut:
            .keyboardShortcut(KeyboardShortcutBinding(keyCode: 49, modifiers: .command, keyLabel: "Space"))
        case .application: .application(path: "")
        case .systemApplication: .systemApplication(path: "")
        case .plugin: .plugin(identifier: RadialPluginPreset.plugins.rawValue)
        case .website: .website(url: "https://")
        case .pasteText: .pasteText("")
        case .folder: .folder(path: "")
        case .shortcut: .shortcut(name: "")
        }
    }
}

enum RadialMenuActionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case unconfigured
    case codexToolbox
    case keyboardShortcut
    case application
    case systemApplication
    case plugin
    case website
    case pasteText
    case folder
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unconfigured: "未设置"
        case .codexToolbox: "Codex 工具箱"
        case .keyboardShortcut: "快捷键"
        case .application: "应用程序"
        case .systemApplication: "系统应用"
        case .plugin: "插件"
        case .website: "网址"
        case .pasteText: "粘贴文本"
        case .folder: "文件夹"
        case .shortcut: "快捷指令"
        }
    }

    var systemImage: String {
        switch self {
        case .unconfigured: "plus"
        case .codexToolbox: "shippingbox.fill"
        case .keyboardShortcut: "keyboard"
        case .application: "app.fill"
        case .systemApplication: "macwindow"
        case .plugin: "puzzlepiece.extension.fill"
        case .website: "globe"
        case .pasteText: "doc.on.clipboard.fill"
        case .folder: "folder.fill"
        case .shortcut: "square.stack.3d.up.fill"
        }
    }
}

struct RadialMenuItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var systemImage: String
    var action: RadialMenuAction
    var triggerShortcut: KeyboardShortcutBinding?

    init(
        id: UUID = UUID(),
        title: String,
        systemImage: String,
        action: RadialMenuAction,
        triggerShortcut: KeyboardShortcutBinding? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
        self.triggerShortcut = triggerShortcut
    }
}

struct RadialMenuProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var applicationPath: String
    var bundleIdentifier: String
    var isDefault: Bool
    var items: [RadialMenuItem]

    init(
        id: UUID = UUID(),
        name: String,
        applicationPath: String,
        bundleIdentifier: String,
        isDefault: Bool = false,
        items: [RadialMenuItem]
    ) {
        self.id = id
        self.name = name
        self.applicationPath = applicationPath
        self.bundleIdentifier = bundleIdentifier
        self.isDefault = isDefault
        self.items = items
    }

    var isGlobal: Bool {
        bundleIdentifier == RadialMenuDefaults.globalBundleIdentifier
    }
}

enum RadialMenuProfileResolver {
    static func profile(
        for bundleIdentifier: String?,
        profiles: [RadialMenuProfile],
        globalModeEnabled: Bool = false
    ) -> RadialMenuProfile? {
        if globalModeEnabled,
           let global = profiles.first(where: \.isGlobal) {
            return global
        }
        if let bundleIdentifier,
           let matched = profiles.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return matched
        }
        return profiles.first(where: \RadialMenuProfile.isDefault) ?? profiles.first
    }

    static func items(
        for bundleIdentifier: String?,
        profiles: [RadialMenuProfile],
        globalModeEnabled: Bool = false
    ) -> [RadialMenuItem] {
        profile(
            for: bundleIdentifier,
            profiles: profiles,
            globalModeEnabled: globalModeEnabled
        )?.items
            ?? RadialMenuDefaults.items
    }
}

enum RadialPluginPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case plugins
    case skills
    case automations
    case openAIDocs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plugins: "插件与 Apps"
        case .skills: "Skills"
        case .automations: "定时任务"
        case .openAIDocs: "OpenAI 文档"
        }
    }

    var systemImage: String {
        switch self {
        case .plugins: "puzzlepiece.extension.fill"
        case .skills: "sparkles"
        case .automations: "clock.badge.fill"
        case .openAIDocs: "book.closed.fill"
        }
    }

    var toolboxAction: ToolboxAction {
        switch self {
        case .plugins: .plugins
        case .skills: .skills
        case .automations: .automations
        case .openAIDocs: .openAIDocs
        }
    }
}

enum RadialMenuDefaults {
    static let globalBundleIdentifier = "com.codexmicro.radial.global"

    static let items: [RadialMenuItem] = [
        RadialMenuItem(title: "打开 Codex", systemImage: "keyboard.fill", action: .codexToolbox(.openCodex)),
        RadialMenuItem(title: "侧边栏", systemImage: "sidebar.left", action: .codexToolbox(.toggleSidebar)),
        RadialMenuItem(title: "上一个任务", systemImage: "chevron.left.2", action: .codexToolbox(.previousTask)),
        RadialMenuItem(title: "下一个任务", systemImage: "chevron.right.2", action: .codexToolbox(.nextTask)),
        RadialMenuItem(title: "搜索任务", systemImage: "magnifyingglass", action: .codexToolbox(.searchTasks)),
        RadialMenuItem(title: "终端", systemImage: "terminal.fill", action: .codexToolbox(.terminal)),
        RadialMenuItem(title: "Skills", systemImage: "sparkles", action: .codexToolbox(.skills)),
    ]

    /// 新增应用从均匀的空轮盘开始，避免把 ChatGPT 的操作误套到其他应用。
    static var emptyItems: [RadialMenuItem] {
        (0..<8).map { _ in
            RadialMenuItem(title: "未设置", systemImage: "plus", action: .unconfigured)
        }
    }

    static var globalItems: [RadialMenuItem] {
        [
            RadialMenuItem(
                title: "ChatGPT",
                systemImage: "app.fill",
                action: .application(path: "/Applications/ChatGPT.app")
            ),
            RadialMenuItem(
                title: "微信",
                systemImage: "app.fill",
                action: .application(path: "/Applications/WeChat.app")
            ),
            RadialMenuItem(
                title: "飞书",
                systemImage: "app.fill",
                action: .application(path: "/Applications/Lark.app")
            ),
            RadialMenuItem(
                title: "剪映",
                systemImage: "app.fill",
                action: .application(path: "/Applications/VideoFusion-macOS.app")
            ),
            RadialMenuItem(
                title: "App Store",
                systemImage: "app.fill",
                action: .application(path: "/System/Applications/App Store.app")
            ),
            RadialMenuItem(
                title: "系统设置",
                systemImage: "macwindow",
                action: .systemApplication(path: "/System/Applications/System Settings.app")
            ),
            RadialMenuItem(
                title: "谷歌浏览器",
                systemImage: "app.fill",
                action: .application(path: "/Applications/Google Chrome.app")
            ),
            RadialMenuItem(
                title: "终端",
                systemImage: "app.fill",
                action: .application(path: "/System/Applications/Utilities/Terminal.app")
            ),
        ]
    }

    static func initialGlobalModeEnabled(savedProfilesExist: Bool, storedValue: Bool?) -> Bool {
        storedValue ?? !savedProfilesExist
    }

    static func globalProfile(items: [RadialMenuItem]? = nil) -> RadialMenuProfile {
        RadialMenuProfile(
            name: "全局模式",
            applicationPath: "",
            bundleIdentifier: globalBundleIdentifier,
            items: items ?? globalItems
        )
    }

    static func chatGPTProfile(items: [RadialMenuItem] = items) -> RadialMenuProfile {
        RadialMenuProfile(
            name: "ChatGPT",
            applicationPath: "/Applications/ChatGPT.app",
            bundleIdentifier: "com.openai.chat",
            isDefault: true,
            items: items
        )
    }
}

enum RadialIconCatalog {
    static let codexSymbols: [String] = Array(Set(ToolboxAction.allCases.map(\.systemImage))).sorted()

    static let systemSymbols: [String] = [
        "app.fill", "app.badge.fill", "apps.iphone", "square.grid.2x2.fill", "circle.grid.3x3.fill",
        "command", "option", "control", "shift", "keyboard", "keyboard.badge.ellipsis",
        "bolt.fill", "bolt.circle.fill", "sparkles", "wand.and.stars", "brain.head.profile",
        "brain.head.profile.fill", "shippingbox.fill", "archivebox.fill", "tray.fill", "inbox.fill",
        "folder.fill", "folder.badge.plus", "doc.fill", "doc.text.fill", "doc.on.doc.fill",
        "doc.on.clipboard.fill", "paperclip", "link", "globe", "safari.fill", "network",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "curlybraces", "ladybug.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "slider.horizontal.3",
        "play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill", "record.circle",
        "paperplane.fill", "message.fill", "bubble.left.fill", "text.bubble.fill", "quote.bubble.fill",
        "magnifyingglass", "doc.text.magnifyingglass", "viewfinder", "scope", "eye.fill",
        "photo.fill", "camera.fill", "video.fill", "music.note", "headphones", "waveform",
        "mic.fill", "speaker.wave.2.fill", "paintbrush.fill", "paintpalette.fill", "eyedropper.full",
        "clock.fill", "timer", "calendar", "bell.fill", "flag.fill", "pin.fill", "bookmark.fill",
        "star.fill", "heart.fill", "hand.thumbsup.fill", "checkmark.circle.fill", "xmark.circle.fill",
        "plus.circle.fill", "minus.circle.fill", "questionmark.circle.fill", "info.circle.fill",
        "exclamationmark.triangle.fill", "lock.fill", "lock.open.fill", "shield.fill", "key.fill",
        "person.fill", "person.2.fill", "person.crop.circle.fill", "at", "number", "textformat",
        "arrow.left", "arrow.right", "arrow.up", "arrow.down", "arrow.clockwise", "arrow.counterclockwise",
        "arrow.triangle.branch", "arrow.merge", "arrow.up.right.square.fill", "arrowshape.turn.up.right.fill",
        "sidebar.left", "sidebar.right", "rectangle.split.2x1.fill", "rectangle.bottomthird.inset.filled",
        "macbook", "desktopcomputer", "display", "externaldrive.fill", "internaldrive.fill", "memorychip.fill",
        "cpu.fill", "wifi", "antenna.radiowaves.left.and.right", "icloud.fill", "cloud.fill",
        "square.and.arrow.up.fill", "square.and.arrow.down.fill", "trash.fill", "pencil", "scissors",
        "list.bullet", "list.clipboard.fill", "checklist", "tablecells.fill", "chart.bar.fill", "map.fill",
        "location.fill", "house.fill", "building.2.fill", "cart.fill", "creditcard.fill", "gift.fill",
        "lightbulb.fill", "flame.fill", "leaf.fill", "moon.fill", "sun.max.fill", "power",
        "ellipsis.circle.fill", "ellipsis.rectangle.fill", "puzzlepiece.extension.fill", "square.stack.3d.up.fill",
    ]

    static let allSymbols: [String] = Array(Set(codexSymbols + systemSymbols)).sorted()
}
