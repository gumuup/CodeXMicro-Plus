// Adapted from VincentKingHsu/vRemoter (MIT); see ThirdParty/vRemoter/LICENSE.
import AppKit
import CoreGraphics
import Foundation

enum SupportedRemoteID: String, CaseIterable, Identifiable, Codable, Sendable {
    case chromecast
    case x6
    case mxMaster3s

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chromecast: "Chromecast Voice Remote"
        case .x6: "X6 Remote"
        case .mxMaster3s: "MX Master 3S"
        }
    }

    var signature: String {
        switch self {
        case .chromecast: "18D1 · 9450"
        case .x6: "1D5A · C081"
        case .mxMaster3s: "046D · 蓝牙 / Bolt"
        }
    }
}

struct RemoteButtonDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let defaultTarget: RemoteMappingTarget
    let voiceControlled: Bool
    let remappable: Bool

    init(
        id: String,
        title: String,
        symbol: String,
        defaultTarget: RemoteMappingTarget,
        voiceControlled: Bool = false,
        remappable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.defaultTarget = defaultTarget
        self.voiceControlled = voiceControlled
        self.remappable = remappable
    }
}

enum RemoteProfiles {
    /// Describes pass-through behavior; these labels must not synthesize events.
    static func mxNativeTitle(for id: String) -> String {
        switch id {
        case "mx0050": "左键点击"
        case "mx0051": "右键点击"
        case "mx0052": "中键点击"
        case "mx0053": "后退"
        case "mx0056": "前进"
        case "mx00C3": "拇指手势（驱动处理）"
        case "mx00C4": "切换滚轮模式"
        case "mxScrollUp": "向上滚动"
        case "mxScrollDown": "向下滚动"
        case "mxScrollLeft": "向左滚动"
        case "mxScrollRight": "向右滚动"
        default: "设备原生功能"
        }
    }

    static let chromecastButtons: [RemoteButtonDefinition] = [
        .init(id: "03", title: "方向上", symbol: "arrow.up", defaultTarget: .arrowUp),
        .init(id: "04", title: "方向下", symbol: "arrow.down", defaultTarget: .arrowDown),
        .init(id: "05", title: "方向左", symbol: "arrow.left", defaultTarget: .arrowLeft),
        .init(id: "06", title: "方向右", symbol: "arrow.right", defaultTarget: .arrowRight),
        .init(id: "07", title: "确认", symbol: "circle.inset.filled", defaultTarget: .returnKey),
        .init(id: "0B", title: "返回", symbol: "chevron.backward", defaultTarget: .escape),
        .init(id: "0A", title: "Home", symbol: "house", defaultTarget: .showDesktop),
        .init(id: "0E", title: "YouTube", symbol: "play.rectangle", defaultTarget: .disabled),
        .init(id: "voice", title: "语音", symbol: "mic", defaultTarget: .voice, voiceControlled: true),
        .init(id: "08", title: "静音", symbol: "speaker.slash", defaultTarget: .mute),
        .init(id: "0F", title: "Netflix", symbol: "n.square", defaultTarget: .disabled),
        .init(id: "01", title: "电源", symbol: "power", defaultTarget: .disabled),
        .init(id: "11", title: "信源", symbol: "rectangle.on.rectangle", defaultTarget: .disabled),
        .init(id: "0C", title: "音量＋", symbol: "speaker.plus", defaultTarget: .volumeUp),
        .init(id: "0D", title: "音量－", symbol: "speaker.minus", defaultTarget: .volumeDown),
    ]

    static func buttons(for remote: SupportedRemoteID) -> [RemoteButtonDefinition] {
        switch remote {
        case .chromecast: chromecastButtons
        case .x6: x6Buttons
        case .mxMaster3s: mxButtons
        }
    }

    static let mxButtons: [RemoteButtonDefinition] = [0x50, 0x51, 0x52, 0x53, 0x56, 0xC3, 0xC4].map { (cid: UInt16) in
        let info = MXMasterProtocol.controlNames[cid]!
        return .init(id: MXMasterProtocol.id(cid), title: info.0, symbol: info.1, defaultTarget: .disabled)
    } + [
        .init(id: "mxScrollUp", title: "主滚轮向上", symbol: "arrow.up", defaultTarget: .disabled),
        .init(id: "mxScrollDown", title: "主滚轮向下", symbol: "arrow.down", defaultTarget: .disabled),
        .init(id: "mxScrollLeft", title: "拇指滚轮向左", symbol: "arrow.left", defaultTarget: .disabled),
        .init(id: "mxScrollRight", title: "拇指滚轮向右", symbol: "arrow.right", defaultTarget: .disabled)
    ]

    static let x6Buttons: [RemoteButtonDefinition] = [
        .init(id: "mouseMode", title: "鼠标模式", symbol: "cursorarrow.motionlines", defaultTarget: .disabled, remappable: false),
        .init(id: "k2A", title: "Delete", symbol: "delete.left", defaultTarget: .deleteBackward),
        .init(id: "cE2", title: "静音", symbol: "speaker.slash", defaultTarget: .mute),
        .init(id: "c224", title: "返回", symbol: "chevron.backward", defaultTarget: .escape),
        .init(id: "k65", title: "菜单", symbol: "line.3.horizontal", defaultTarget: .disabled),
        .init(id: "c196", title: "浏览器/搜索", symbol: "magnifyingglass", defaultTarget: .spotlight),
        .init(id: "k52", title: "方向上", symbol: "arrow.up", defaultTarget: .arrowUp),
        .init(id: "k51", title: "方向下", symbol: "arrow.down", defaultTarget: .arrowDown),
        .init(id: "k50", title: "方向左", symbol: "arrow.left", defaultTarget: .arrowLeft),
        .init(id: "k4F", title: "方向右", symbol: "arrow.right", defaultTarget: .arrowRight),
        .init(id: "k28", title: "OK", symbol: "circle.inset.filled", defaultTarget: .returnKey),
        .init(id: "k4B", title: "PG+", symbol: "arrow.up.to.line", defaultTarget: .pageUp),
        .init(id: "k4E", title: "PG−", symbol: "arrow.down.to.line", defaultTarget: .pageDown),
        .init(id: "voice", title: "语音", symbol: "mic", defaultTarget: .voice, voiceControlled: true),
        .init(id: "cE9", title: "音量＋", symbol: "speaker.plus", defaultTarget: .volumeUp),
        .init(id: "cEA", title: "音量－", symbol: "speaker.minus", defaultTarget: .volumeDown),
        .init(id: "s01", title: "电源", symbol: "power", defaultTarget: .disabled),
    ]
}

enum RemoteMappingTarget: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case disabled
    case voice
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case returnKey
    case escape
    case deleteBackward
    case tab
    case space
    case home
    case end
    case pageUp
    case pageDown
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case showDesktop
    case spotlight
    case commandC
    case commandV
    case commandZ
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "禁用"
        case .voice: "自定义语音输入"
        case .arrowUp: "方向上"
        case .arrowDown: "方向下"
        case .arrowLeft: "方向左"
        case .arrowRight: "方向右"
        case .returnKey: "Return"
        case .escape: "Escape"
        case .deleteBackward: "Delete"
        case .tab: "Tab"
        case .space: "空格"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .volumeUp: "系统音量＋"
        case .volumeDown: "系统音量－"
        case .mute: "系统静音"
        case .playPause: "播放/暂停"
        case .showDesktop: "显示桌面"
        case .spotlight: "Spotlight (⌘Space)"
        case .commandC: "复制 (⌘C)"
        case .commandV: "粘贴 (⌘V)"
        case .commandZ: "撤销 (⌘Z)"
        case .custom: "录制任意按键…"
        }
    }

    var keyboard: (keyCode: CGKeyCode, flags: CGEventFlags)? {
        switch self {
        case .arrowUp: (0x7E, [])
        case .arrowDown: (0x7D, [])
        case .arrowLeft: (0x7B, [])
        case .arrowRight: (0x7C, [])
        case .returnKey: (0x24, [])
        case .escape: (0x35, [])
        case .deleteBackward: (0x33, [])
        case .tab: (0x30, [])
        case .space: (0x31, [])
        case .home: (0x73, [])
        case .end: (0x77, [])
        case .pageUp: (0x74, [])
        case .pageDown: (0x79, [])
        case .showDesktop: (0x67, [.maskSecondaryFn])
        case .spotlight: (0x31, [.maskCommand])
        case .commandC: (0x08, [.maskCommand])
        case .commandV: (0x09, [.maskCommand])
        case .commandZ: (0x06, [.maskCommand])
        default: nil
        }
    }

    var mediaKey: Int32? {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        default: nil
        }
    }

    @MainActor func post(isDown: Bool) {
        guard self != .disabled, self != .voice else { return }
        if let keyboard {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyboard.keyCode,
                keyDown: isDown
            ) else { return }
            event.flags = keyboard.flags
            event.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
            event.post(tap: .cghidEventTap)
        } else if let mediaKey, isDown {
            postMediaKey(mediaKey)
        }
    }

    @MainActor private func postMediaKey(_ key: Int32) {
        func post(state: Int32) {
            let data1 = Int((key << 16) | (state << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )?.cgEvent else { return }
            event.post(tap: .cghidEventTap)
        }
        post(state: 0xA)
        post(state: 0xB)
    }
}
