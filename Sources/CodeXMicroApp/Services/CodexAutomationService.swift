import AppKit
import ApplicationServices

@MainActor
final class CodexAutomationService {
    enum AutomationError: LocalizedError {
        case accessibilityRequired
        case codexNotInstalled
        case taskCouldNotOpen

        var errorDescription: String? {
            switch self {
            case .accessibilityRequired: "请先在系统设置的“隐私与安全性 → 辅助功能”中允许 CodeXMicro++。"
            case .codexNotInstalled: "没有找到 Codex 桌面应用。"
            case .taskCouldNotOpen: "Codex 无法打开这个任务。"
            }
        }
    }

    private var didRequestAccessibilityThisLaunch = false

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
            // Codex exposes Fast mode through the user keybinding, not as a
            // searchable command-menu ID. Keep this in sync with
            // codex-keybindings.json (Ctrl+Shift+F).
            sendKey(3, flags: [.maskControl, .maskShift], to: codexPID)
        case .approve, .send:
            sendKey(36, to: codexPID)
        case .decline:
            sendKey(53, to: codexPID)
        case .newTask:
            sendKey(45, flags: .maskCommand, to: codexPID)
        case .plan:
            sendKey(35, flags: [.maskControl, .maskShift], to: codexPID)
        case .goal:
            // Goal mode is exposed as the /goal composer command rather than
            // a bindable Codex command. Leave the objective for the user to enter.
            sendText("/goal ", to: codexPID)
        case .fork:
            try await runCommandPalette("forkThread", in: codexPID)
        case .reasoningUp:
            // Ctrl+Shift+I is bound to composer.increaseReasoningEffort in
            // codex-keybindings.json. Internal command IDs are not searchable
            // entries in Codex's command menu.
            sendKey(34, flags: [.maskControl, .maskShift], to: codexPID)
        case .reasoningDown:
            // Ctrl+Shift+U is bound to composer.decreaseReasoningEffort.
            sendKey(32, flags: [.maskControl, .maskShift], to: codexPID)
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

    func setVoiceDictation(active: Bool) async throws {
        try requireAccessibility()
        let codexPID = try await activateCodex()
        sendKey(2, flags: [.maskControl, .maskShift], to: codexPID)
    }

    func performJoystick(_ direction: JoystickDirection) async throws {
        switch direction {
        case .left:
            // Codex also supports Cmd+Shift+[ here, but the bracket shortcut
            // can be swallowed or remapped by the active input source.
            try await runShortcut(keyCode: 123, flags: [.maskCommand, .maskAlternate])
        case .right:
            try await runShortcut(keyCode: 124, flags: [.maskCommand, .maskAlternate])
        case .up:
            try await perform(MicroAction.plan)
        case .down:
            try await perform(MicroAction.goal)
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
            running.activate(options: [.activateAllWindows])
            try await Task.sleep(for: .milliseconds(170))
            return running.processIdentifier
        }
        for id in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let running = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try await Task.sleep(for: .milliseconds(350))
            return running.processIdentifier
        }
        throw AutomationError.codexNotInstalled
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
}
