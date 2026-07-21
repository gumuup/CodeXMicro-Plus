import AppKit
import ApplicationServices

@MainActor
final class CodexAutomationService {
    enum AutomationError: LocalizedError {
        case accessibilityRequired
        case codexNotInstalled
        case taskCouldNotOpen
        case codexMenuItemUnavailable(String)
        case radialActionInvalid(String)

        var errorDescription: String? {
            switch self {
            case .accessibilityRequired: "请先在系统设置的“隐私与安全性 → 辅助功能”中允许 CodeXMicro++。"
            case .codexNotInstalled: "没有找到 Codex 桌面应用。"
            case .taskCouldNotOpen: "Codex 无法打开这个任务。"
            case let .codexMenuItemUnavailable(action): "Codex 当前无法执行“\(action)”。"
            case let .radialActionInvalid(action): "轮盘项目“\(action)”尚未配置完整。"
            }
        }
    }

    private var didRequestAccessibilityThisLaunch = false
    private let keybindings = CodexKeybindingResolver()

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        guard !isAccessibilityTrusted else { return }
        if didRequestAccessibilityThisLaunch {
            openAccessibilitySettings()
            return
        }
        promptForAccessibilityOnce()
    }

    private func promptForAccessibilityOnce() {
        guard !isAccessibilityTrusted, !didRequestAccessibilityThisLaunch else { return }
        didRequestAccessibilityThisLaunch = true
        // The exported Core Foundation global is not annotated for Swift 6
        // concurrency; its documented string value is stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openTask(id: String) throws {
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "codex://threads/\(encodedID)"),
              NSWorkspace.shared.open(url) else {
            throw AutomationError.taskCouldNotOpen
        }
    }

    func perform(_ action: MicroAction) async throws {
        if action == .openCodex {
            _ = try await activateCodex()
            return
        }
        try requireAccessibility()
        let codexPID = try await activateCodex()

        switch action {
        case .fast:
            sendCommandShortcut(
                "composer.toggleFastMode",
                fallback: binding(3, [.control]),
                to: codexPID
            )
        case .approve, .send:
            sendKey(36, to: codexPID)
        case .decline:
            sendKey(53, to: codexPID)
        case .newTask:
            sendKey(45, flags: .maskCommand, to: codexPID)
        case .plan:
            sendCommandShortcut(
                "composer.togglePlanMode",
                fallback: binding(1, [.control]),
                to: codexPID
            )
        case .goal:
            // Goal mode is exposed as the /goal composer command rather than
            // a bindable Codex command. Leave the objective for the user to enter.
            sendText("/goal ", to: codexPID)
        case .fork:
            try await runCommandPalette("forkThread", in: codexPID)
        case .reasoningUp:
            sendCommandShortcut(
                "composer.increaseReasoningEffort",
                fallback: binding(24, [.control]),
                to: codexPID
            )
        case .reasoningDown:
            sendCommandShortcut(
                "composer.decreaseReasoningEffort",
                fallback: binding(27, [.control]),
                to: codexPID
            )
        case .openCodex:
            break
        }
    }

    func perform(_ action: ToolboxAction) async throws {
        if let microAction = action.microAction {
            try await perform(microAction)
            return
        }

        if let prompt = action.workflowPrompt {
            try await startNewTask(prompt: prompt)
            return
        }

        switch action {
        case .openAIDocs:
            openURL("https://developers.openai.com/codex")
        case .skills:
            openURL("codex://skills")
        case .automations:
            openURL("codex://automations")
        case .plugins:
            openURL("codex://plugins")
        case .settings:
            openURL("codex://settings")

        case .dictation:
            try await runShortcut(keyCode: 2, flags: [.maskControl, .maskShift])
        case .quickChat:
            try await runShortcut(keyCode: 45, flags: [.maskCommand, .maskAlternate])
        case .searchTasks:
            try await runShortcut(keyCode: 5, flags: .maskCommand)
        case .findInTask:
            try await runShortcut(keyCode: 3, flags: .maskCommand)
        case .previousTask:
            try await runShortcut(keyCode: 33, flags: [.maskCommand, .maskShift])
        case .nextTask:
            try await runShortcut(keyCode: 30, flags: [.maskCommand, .maskShift])
        case .reviewChanges:
            try await runShortcut(keyCode: 5, flags: [.maskControl, .maskShift])
        case .reviewPanel:
            try await runShortcut(keyCode: 11, flags: [.maskCommand, .maskAlternate])
        case .terminal:
            try await runShortcut(keyCode: 50, flags: .maskControl)
        case .clearTerminal:
            try await runShortcut(keyCode: 37, flags: .maskControl)
        case .openFolder:
            try await runShortcut(keyCode: 31, flags: .maskCommand)
        case .commandMenu:
            try await runShortcut(keyCode: 35, flags: [.maskCommand, .maskShift])
        case .historyBack:
            try await runShortcut(keyCode: 33, flags: .maskCommand)
        case .historyForward:
            try await runShortcut(keyCode: 30, flags: .maskCommand)
        case .toggleSidebar:
            try await runShortcut(keyCode: 11, flags: .maskCommand)
        case .keyboardShortcuts:
            try await runShortcut(keyCode: 44, flags: [.maskCommand, .maskShift])
        case .toggleBottomPanel:
            try await runShortcut(keyCode: 38, flags: .maskCommand)
        case .fontUp:
            try await runShortcut(keyCode: 24, flags: [.maskCommand, .maskShift])
        case .fontDown:
            try await runShortcut(keyCode: 27, flags: .maskCommand)

        case .archiveTask:
            try await runPaletteCommand("archiveThread")
        case .pinTask:
            try await runPaletteCommand("toggleThreadPin")
        case .copyTaskMarkdown:
            try await runPaletteCommand("copyConversationMarkdown")
        case .browser:
            try await runPaletteCommand("openBrowserTab")
        case .attachFiles:
            try await runPaletteCommand("composer.addFiles")
        case .addPhotos:
            try await runPaletteCommand("composer.addPhotos")
        case .gitCommit:
            try await runPaletteCommand("git.commit")
        case .createPullRequest:
            try await runPaletteCommand("git.createPullRequest")

        case .fast, .approve, .decline, .send, .newTask, .fork, .plan, .openCodex,
             .reasoningUp, .reasoningDown, .debug, .runTests, .refactor, .explainCodebase,
             .frontendPolish, .gitStatus, .newBranch, .mergeBranch, .reviewPullRequest,
             .commitAndPush:
            break
        }
    }

    func perform(_ action: RadialMenuAction) async throws {
        switch action {
        case .unconfigured:
            throw AutomationError.radialActionInvalid("未设置")

        case let .codexToolbox(toolboxAction):
            try await perform(toolboxAction)

        case let .keyboardShortcut(binding):
            guard !binding.isMouse else {
                throw AutomationError.radialActionInvalid("键盘快捷键")
            }
            try requireAccessibility()
            sendKeyGlobally(
                CGKeyCode(binding.keyCode),
                flags: binding.modifiers.cgEventFlags
            )

        case let .application(path), let .systemApplication(path):
            guard !path.isEmpty else { throw AutomationError.radialActionInvalid("应用程序") }
            let url = URL(fileURLWithPath: path)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)

        case let .plugin(identifier):
            guard let plugin = RadialPluginPreset(rawValue: identifier) else {
                throw AutomationError.radialActionInvalid("插件")
            }
            try await perform(plugin.toolboxAction)

        case let .website(value):
            let normalized = value.contains("://") ? value : "https://\(value)"
            guard let url = URL(string: normalized), NSWorkspace.shared.open(url) else {
                throw AutomationError.radialActionInvalid("网址")
            }

        case let .pasteText(text):
            guard !text.isEmpty else { throw AutomationError.radialActionInvalid("粘贴文本") }
            try requireAccessibility()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            try? await Task.sleep(for: .milliseconds(80))
            sendKeyGlobally(9, flags: .maskCommand)

        case let .folder(path):
            guard !path.isEmpty, NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                throw AutomationError.radialActionInvalid("文件夹")
            }

        case let .shortcut(name):
            guard !name.isEmpty else { throw AutomationError.radialActionInvalid("快捷指令") }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }
    }

    func setVoiceDictation(active: Bool) async throws {
        try requireAccessibility()
        _ = try await activateCodex()
        // The Edit > “开始听写…” item belongs to macOS and is not Codex's
        // composer command. Invoke Codex's configured command shortcut instead.
        // A short settling delay matters for Electron after app activation.
        try? await Task.sleep(for: .milliseconds(180))
        sendCommandShortcutGlobally(
            "composer.startDictation",
            fallback: binding(2, [.control, .shift])
        )
    }

    func performJoystick(_ direction: JoystickDirection) async throws {
        switch direction {
        case .left:
            let codexPID = try await activateCodex()
            guard pressMenuItem(
                in: codexPID,
                menuTitles: ["View", "显示", "顯示"],
                itemTitleFragments: ["Previous Chat", "上一个对话", "上一個對話"]
            ) else {
                throw AutomationError.codexMenuItemUnavailable("上一个任务")
            }
        case .right:
            let codexPID = try await activateCodex()
            guard pressMenuItem(
                in: codexPID,
                menuTitles: ["View", "显示", "顯示"],
                itemTitleFragments: ["Next Chat", "下一个对话", "下一個對話"]
            ) else {
                throw AutomationError.codexMenuItemUnavailable("下一个任务")
            }
        case .up:
            try requireAccessibility()
            _ = try await activateCodex()
            try? await Task.sleep(for: .milliseconds(180))
            sendCommandShortcutGlobally(
                "composer.togglePlanMode",
                fallback: binding(1, [.control])
            )
        case .down:
            try requireAccessibility()
            _ = try await activateCodex()
            sendTextGlobally("/goal ")
        }
    }

    private func requireAccessibility() throws {
        guard isAccessibilityTrusted else {
            // An action may be retried many times while the user is deciding
            // whether to grant access. Only the explicit Settings button should
            // reopen System Settings after the first system prompt.
            promptForAccessibilityOnce()
            throw AutomationError.accessibilityRequired
        }
    }

    private func activateCodex() async throws -> pid_t {
        let bundleIDs = ["com.openai.codex", "com.openai.chat", "com.openai.ChatGPT"]
        if let running = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let id = app.bundleIdentifier else { return false }
            return bundleIDs.contains(id)
        }) {
            running.unhide()
            if let url = running.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.addsToRecentItems = false
                let activated = try await NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                )
                await waitUntilFrontmost(activated)
                return activated.processIdentifier
            }
            running.activate(options: [.activateAllWindows])
            await waitUntilFrontmost(running)
            return running.processIdentifier
        }
        for id in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let running = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            running.activate(options: [.activateAllWindows])
            await waitUntilFrontmost(running)
            return running.processIdentifier
        }
        throw AutomationError.codexNotInstalled
    }

    private func waitUntilFrontmost(_ application: NSRunningApplication) async {
        for _ in 0..<12 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                return
            }
            application.activate(options: [.activateAllWindows])
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func pressMenuItem(
        in pid: pid_t,
        menuTitles: [String],
        itemTitleFragments: [String]
    ) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        guard let menuBar = axElementAttribute(application, kAXMenuBarAttribute) else {
            return false
        }
        guard let menuBarItem = axChildren(menuBar).first(where: { item in
            guard let title = axStringAttribute(item, kAXTitleAttribute) else { return false }
            return menuTitles.contains { title.caseInsensitiveCompare($0) == .orderedSame }
        }) else {
            return false
        }

        return axDescendants(menuBarItem, maximumDepth: 3).contains { item in
            guard let title = axStringAttribute(item, kAXTitleAttribute) else { return false }
            guard itemTitleFragments.contains(where: {
                title.localizedCaseInsensitiveContains($0)
            }) else {
                return false
            }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
    }

    private func axElementAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as! AXUIElement?
    }

    private func axStringAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func axDescendants(
        _ element: AXUIElement,
        maximumDepth: Int
    ) -> [AXUIElement] {
        guard maximumDepth > 0 else { return [] }
        let children = axChildren(element)
        return children + children.flatMap {
            axDescendants($0, maximumDepth: maximumDepth - 1)
        }
    }

    private func runCommandPalette(_ command: String, in codexPID: pid_t) async throws {
        sendKey(40, flags: .maskCommand, to: codexPID)
        try await Task.sleep(for: .milliseconds(320))
        sendText(command, to: codexPID)
        try await Task.sleep(for: .milliseconds(220))
        sendKey(36, to: codexPID)
    }

    private func runShortcut(keyCode: CGKeyCode, flags: CGEventFlags) async throws {
        try requireAccessibility()
        let codexPID = try await activateCodex()
        sendKey(keyCode, flags: flags, to: codexPID)
    }

    private func runGlobalShortcut(keyCode: CGKeyCode, flags: CGEventFlags) async throws {
        try requireAccessibility()
        _ = try await activateCodex()
        sendKeyGlobally(keyCode, flags: flags)
    }

    private func runPaletteCommand(_ command: String) async throws {
        try requireAccessibility()
        let codexPID = try await activateCodex()
        try await runCommandPalette(command, in: codexPID)
    }

    private func startNewTask(prompt: String) async throws {
        try requireAccessibility()
        let codexPID = try await activateCodex()
        sendKey(45, flags: .maskCommand, to: codexPID)
        try await Task.sleep(for: .milliseconds(320))
        sendText(prompt, to: codexPID)
        try await Task.sleep(for: .milliseconds(120))
        sendKey(36, to: codexPID)
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        up?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    private func sendCommandShortcut(
        _ command: String,
        fallback: KeyboardShortcutBinding,
        to pid: pid_t
    ) {
        let resolved = keybindings.binding(for: command, fallback: fallback)
        sendKey(CGKeyCode(resolved.keyCode), flags: resolved.modifiers.cgEventFlags, to: pid)
    }

    private func sendCommandShortcutGlobally(
        _ command: String,
        fallback: KeyboardShortcutBinding
    ) {
        let resolved = keybindings.binding(for: command, fallback: fallback)
        sendKeyGlobally(
            CGKeyCode(resolved.keyCode),
            flags: resolved.modifiers.cgEventFlags
        )
    }

    private func sendKeyGlobally(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = []
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifierKeys: [(CGKeyCode, CGEventFlags)] = [
            (55, .maskCommand),
            (59, .maskControl),
            (58, .maskAlternate),
            (56, .maskShift),
        ].filter { flags.contains($0.1) }
        var accumulatedFlags: CGEventFlags = []
        for (modifierKey, modifierFlag) in modifierKeys {
            accumulatedFlags.insert(modifierFlag)
            postGlobalKeyEvent(
                modifierKey,
                keyDown: true,
                flags: accumulatedFlags,
                source: source
            )
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        up?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        for (modifierKey, modifierFlag) in modifierKeys.reversed() {
            accumulatedFlags.remove(modifierFlag)
            postGlobalKeyEvent(
                modifierKey,
                keyDown: false,
                flags: accumulatedFlags,
                source: source
            )
        }
    }

    private func postGlobalKeyEvent(
        _ keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags,
        source: CGEventSource?
    ) {
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: keyDown
        )
        event?.flags = flags
        event?.setIntegerValueField(
            .eventSourceUserData,
            value: ShortcutEventMarker.codexAutomation
        )
        event?.post(tap: .cghidEventTap)
    }

    private func binding(
        _ keyCode: UInt16,
        _ modifiers: ShortcutModifiers
    ) -> KeyboardShortcutBinding {
        KeyboardShortcutBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            keyLabel: ShortcutKeyCatalog.label(for: keyCode) ?? ""
        )
    }

    private func sendText(_ text: String, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let scalars = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        scalars.withUnsafeBufferPointer { buffer in
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        down?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        up?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    private func sendTextGlobally(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let scalars = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        scalars.withUnsafeBufferPointer { buffer in
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        down?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        up?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

private extension ShortcutModifiers {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}
