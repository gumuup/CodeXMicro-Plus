import AppKit
import Combine
import Foundation

@MainActor
final class CodexStore: ObservableObject {
    @Published private(set) var tasks: [CodexTask] = []
    @Published private(set) var reasoningLevel: ReasoningLevel = .medium
    @Published private(set) var isFastModeEnabled = false
    @Published private(set) var isCodexRunning = false
    @Published private(set) var weeklyQuota: WeeklyQuota?
    @Published private(set) var lifetimeTokens: Int64?
    @Published private(set) var codexUsageMetric: CodexUsageMetric
    @Published var feedbackMessage: String?
    @Published var labelsVisible = true
    @Published var isVoicePressed = false
    @Published private(set) var shortcutBindings: [ShortcutTarget: KeyboardShortcutBinding]
    @Published private(set) var shortcutRecordingTarget: ShortcutTarget?

    @Published var hapticStrength: HapticStrength {
        didSet { UserDefaults.standard.set(hapticStrength.rawValue, forKey: Keys.hapticStrength) }
    }
    @Published var keySoundEnabled: Bool {
        didSet { UserDefaults.standard.set(keySoundEnabled, forKey: Keys.keySound) }
    }
    @Published var panelPosition: PanelPosition {
        didSet { UserDefaults.standard.set(panelPosition.rawValue, forKey: Keys.panelPosition) }
    }

    private enum Keys {
        static let hapticStrength = "hapticStrength"
        static let keySound = "keySoundEnabled"
        static let panelPosition = "panelPosition"
        static let seen = "seenTasks"
        static let fastMode = "fastModeEnabled"
        static let codexUsageMetric = "codexUsageMetric"
        static let shortcutBindings = "shortcutBindings.v1"
        static let shortcutDefaultsVersion = "shortcutDefaultsVersion"
    }

    private enum AutomationRequest {
        case micro(MicroAction, successMessage: String?)
        case toolbox(ToolboxAction)
        case joystick(JoystickDirection)
        case voice(active: Bool)
        case openTask(CodexTask, index: Int)

        var isReasoningAdjustment: Bool {
            guard case let .micro(action, _) = self else { return false }
            return action == .reasoningUp || action == .reasoningDown
        }
    }

    private let stateService: CodexStateService
    let automation: CodexAutomationService
    let haptics: HapticService
    private let shortcutService: ShortcutService
    private var pollingTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var shortcutRecordingTimeoutTask: Task<Void, Never>?
    private let automationQueue = SerialAsyncQueue<AutomationRequest>()
    private var isVoiceAutomationActive = false
    private var seen: [String: Int64]
    private var pendingReasoningLevel: ReasoningLevel?
    private var pendingReasoningDeadline = Date.distantPast

    init(
        stateService: CodexStateService = CodexStateService(),
        automation: CodexAutomationService = CodexAutomationService(),
        haptics: HapticService = HapticService(),
        shortcutService: ShortcutService = ShortcutService()
    ) {
        self.stateService = stateService
        self.automation = automation
        self.haptics = haptics
        self.shortcutService = shortcutService
        self.hapticStrength = HapticStrength(rawValue: UserDefaults.standard.string(forKey: Keys.hapticStrength) ?? "standard") ?? .standard
        self.keySoundEnabled = UserDefaults.standard.object(forKey: Keys.keySound) as? Bool ?? true
        self.panelPosition = PanelPosition(
            rawValue: UserDefaults.standard.string(forKey: Keys.panelPosition) ?? "top"
        ) ?? .top
        self.isFastModeEnabled = UserDefaults.standard.bool(forKey: Keys.fastMode)
        self.codexUsageMetric = CodexUsageMetric(
            rawValue: UserDefaults.standard.string(forKey: Keys.codexUsageMetric) ?? ""
        ) ?? .weeklyRemaining
        self.seen = UserDefaults.standard.dictionary(forKey: Keys.seen) as? [String: Int64] ?? [:]
        let savedShortcutBindings = UserDefaults.standard.data(forKey: Keys.shortcutBindings).flatMap {
            try? JSONDecoder().decode([ShortcutTarget: KeyboardShortcutBinding].self, from: $0)
        }
        let shouldInstallShortcutDefaults = savedShortcutBindings == nil
            || UserDefaults.standard.integer(forKey: Keys.shortcutDefaultsVersion) < ShortcutDefaults.currentVersion
        if shouldInstallShortcutDefaults {
            let migratedBindings = ShortcutDefaults.merging(into: savedShortcutBindings ?? [:])
            self.shortcutBindings = migratedBindings
            if let data = try? JSONEncoder().encode(migratedBindings) {
                UserDefaults.standard.set(data, forKey: Keys.shortcutBindings)
                UserDefaults.standard.set(ShortcutDefaults.currentVersion, forKey: Keys.shortcutDefaultsVersion)
            }
        } else {
            self.shortcutBindings = savedShortcutBindings ?? [:]
        }
        self.shortcutRecordingTarget = nil
    }

    deinit {
        pollingTask?.cancel()
        feedbackTask?.cancel()
        shortcutRecordingTimeoutTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }
        shortcutService.start(
            onTrigger: { [weak self] target in self?.triggerShortcut(target) },
            onCapture: { [weak self] event in self?.handleShortcutCapture(event) }
        )
        let registrationFailures = shortcutService.update(bindings: shortcutBindings)
        if let target = registrationFailures.first, let binding = shortcutBindings[target] {
            showFeedback("\(binding.displayName) 已被系统或其他应用占用")
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .milliseconds(1_200))
            }
        }
    }

    func refresh() async {
        isCodexRunning = NSWorkspace.shared.runningApplications.contains { application in
            guard let identifier = application.bundleIdentifier else { return false }
            return ["com.openai.codex", "com.openai.chat", "com.openai.ChatGPT"].contains(identifier)
        }
        let snapshot = await stateService.loadSnapshot(seen: seen, includeLiveQuota: isCodexRunning)
        tasks = snapshot.tasks
        if let level = snapshot.reasoningLevel {
            if let pendingReasoningLevel {
                if level == pendingReasoningLevel || Date() >= pendingReasoningDeadline {
                    reasoningLevel = level
                    self.pendingReasoningLevel = nil
                }
            } else {
                reasoningLevel = level
            }
        }
        weeklyQuota = snapshot.weeklyQuota
        if let tokens = snapshot.lifetimeTokens { lifetimeTokens = tokens }
    }

    func task(at index: Int) -> CodexTask? {
        tasks.indices.contains(index) ? tasks[index] : nil
    }

    func openTask(at index: Int) {
        guard let task = task(at: index) else { return }
        tactilePress()
        enqueueAutomation(.openTask(task, index: index))
    }

    func perform(_ action: MicroAction) {
        tactilePress()
        enqueueAutomation(.micro(action, successMessage: action.accessibilityLabel))
    }

    func perform(_ action: ToolboxAction) {
        tactilePress()
        if let microAction = action.microAction {
            enqueueAutomation(.micro(microAction, successMessage: action.title))
        } else {
            enqueueAutomation(.toolbox(action))
        }
    }

    func beginVoice() {
        guard !isVoicePressed else { return }
        isVoicePressed = true
        tactilePress()
        enqueueAutomation(.voice(active: true))
    }

    func endVoice() {
        guard isVoicePressed else { return }
        isVoicePressed = false
        haptics.press(strength: hapticStrength, soundEnabled: false)
        enqueueAutomation(.voice(active: false))
    }

    func performJoystick(_ direction: JoystickDirection) {
        enqueueAutomation(.joystick(direction))
    }

    func joystickDetent() {
        haptics.joystickDetent(strength: hapticStrength)
    }

    func adjustReasoning(by delta: Int) {
        guard delta != 0 else { return }
        let action: MicroAction = delta > 0 ? .reasoningUp : .reasoningDown
        let next = reasoningLevel.stepped(by: delta > 0 ? 1 : -1)
        guard next != reasoningLevel else {
            haptics.detent(strength: hapticStrength)
            showFeedback(delta > 0 ? "已是最高推理强度" : "已是最低推理强度")
            return
        }
        reasoningLevel = next
        pendingReasoningLevel = next
        pendingReasoningDeadline = Date().addingTimeInterval(3)
        haptics.detent(strength: hapticStrength)
        enqueueAutomation(.micro(action, successMessage: nil))
        showFeedback("推理强度：\(next.label)")
    }

    func toggleLayer() {
        labelsVisible.toggle()
        tactilePress()
        showFeedback(labelsVisible ? "已显示按键标注" : "已隐藏按键标注")
    }

    func hoverDetent() {
        haptics.detent(strength: hapticStrength)
    }

    func activateCodexStatusButton() {
        guard isCodexRunning else {
            perform(MicroAction.openCodex)
            return
        }
        tactilePress()
        codexUsageMetric.toggle()
        UserDefaults.standard.set(codexUsageMetric.rawValue, forKey: Keys.codexUsageMetric)
        switch codexUsageMetric {
        case .weeklyRemaining:
            showFeedback("本周剩余 \(weeklyQuota?.remainingPercent.description ?? "--")% Token")
        case .lifetimeConsumed:
            showFeedback("累计消耗 \(TokenCountFormatter.compact(lifetimeTokens)) Token")
        }
    }

    func requestAccessibility() {
        automation.requestAccessibility()
    }

    func shortcut(for target: ShortcutTarget) -> KeyboardShortcutBinding? {
        shortcutBindings[target]
    }

    func beginShortcutRecording(for target: ShortcutTarget) {
        shortcutRecordingTimeoutTask?.cancel()
        shortcutRecordingTarget = target
        shortcutService.beginRecording(for: target)
        showFeedback("为 \(target.title) 按下快捷键 · Esc 取消 · Delete 清除")
        shortcutRecordingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, self?.shortcutRecordingTarget == target else { return }
            self?.cancelShortcutRecording(message: "快捷键设置已超时")
        }
    }

    func cancelShortcutRecording() {
        cancelShortcutRecording(message: "已取消快捷键设置")
    }

    func clearShortcut(for target: ShortcutTarget) {
        shortcutBindings.removeValue(forKey: target)
        if shortcutRecordingTarget == target {
            shortcutRecordingTarget = nil
            shortcutService.cancelRecording()
        }
        persistShortcuts()
        showFeedback("已清除 \(target.title) 的快捷键")
    }

    private func tactilePress() {
        haptics.press(strength: hapticStrength, soundEnabled: keySoundEnabled)
    }

    private func triggerShortcut(_ target: ShortcutTarget) {
        switch target {
        case .agent1: openTask(at: 0)
        case .agent2: openTask(at: 1)
        case .agent3: openTask(at: 2)
        case .agent4: openTask(at: 3)
        case .agent5: openTask(at: 4)
        case .agent6: openTask(at: 5)
        case .joystickUp: performJoystick(.up)
        case .joystickRight: performJoystick(.right)
        case .joystickDown: performJoystick(.down)
        case .joystickLeft: performJoystick(.left)
        case .fast: perform(MicroAction.fast)
        case .approve: perform(MicroAction.approve)
        case .decline: perform(MicroAction.decline)
        case .newTask: perform(MicroAction.newTask)
        case .toggleLabels: toggleLayer()
        case .voice:
            isVoicePressed ? endVoice() : beginVoice()
        case .codexStatus: activateCodexStatusButton()
        case .reasoningDown: adjustReasoning(by: -1)
        case .reasoningUp: adjustReasoning(by: 1)
        }
    }

    private func handleShortcutCapture(_ event: ShortcutService.CaptureEvent) {
        switch event {
        case let .captured(target, binding):
            shortcutRecordingTimeoutTask?.cancel()
            let reassignedTarget = shortcutBindings.first(where: {
                $0.key != target && $0.value == binding
            })?.key
            if let reassignedTarget {
                shortcutBindings.removeValue(forKey: reassignedTarget)
            }
            shortcutBindings[target] = binding
            shortcutRecordingTarget = nil
            let registrationFailures = persistShortcuts()
            if registrationFailures.contains(target) {
                shortcutBindings.removeValue(forKey: target)
                _ = persistShortcuts()
                showFeedback("\(binding.displayName) 已被系统或其他应用占用，请换一个快捷键")
                return
            }
            if let reassignedTarget {
                showFeedback("\(binding.displayName) 已从 \(reassignedTarget.title) 改绑到 \(target.title)")
            } else {
                showFeedback("\(target.title)：\(binding.displayName)")
            }
        case let .cleared(target):
            shortcutRecordingTimeoutTask?.cancel()
            shortcutBindings.removeValue(forKey: target)
            shortcutRecordingTarget = nil
            persistShortcuts()
            showFeedback("已清除 \(target.title) 的快捷键")
        case .cancelled:
            shortcutRecordingTimeoutTask?.cancel()
            shortcutRecordingTarget = nil
            if feedbackMessage?.contains("超时") != true {
                showFeedback("已取消快捷键设置")
            }
        case let .invalid(message):
            showFeedback(message)
        }
    }

    private func cancelShortcutRecording(message: String) {
        guard shortcutRecordingTarget != nil else { return }
        shortcutRecordingTimeoutTask?.cancel()
        shortcutRecordingTarget = nil
        showFeedback(message)
        shortcutService.cancelRecording()
    }

    @discardableResult
    private func persistShortcuts() -> Set<ShortcutTarget> {
        let failures = shortcutService.update(bindings: shortcutBindings)
        guard let data = try? JSONEncoder().encode(shortcutBindings) else { return failures }
        UserDefaults.standard.set(data, forKey: Keys.shortcutBindings)
        return failures
    }

    private func enqueueAutomation(_ request: AutomationRequest) {
        automationQueue.enqueue(request) { [weak self] request in
            await self?.executeAutomation(request)
        }
    }

    private func executeAutomation(_ request: AutomationRequest) async {
        do {
            switch request {
            case let .micro(action, successMessage):
                try await automation.perform(action)
                if action == .fast {
                    isFastModeEnabled.toggle()
                    UserDefaults.standard.set(isFastModeEnabled, forKey: Keys.fastMode)
                    showFeedback(isFastModeEnabled ? "已启用 Fast 模式" : "已关闭 Fast 模式")
                } else if let successMessage {
                    showFeedback(successMessage)
                }

                if request.isReasoningAdjustment {
                    try? await Task.sleep(for: .milliseconds(260))
                    if automationQueue.first?.isReasoningAdjustment != true {
                        await refresh()
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(500))
                    await refresh()
                }

            case let .toolbox(action):
                try await automation.perform(action)
                showFeedback(action.title)
                try? await Task.sleep(for: .milliseconds(350))
                await refresh()

            case let .joystick(direction):
                try await automation.performJoystick(direction)
                showFeedback("已执行：\(direction.title)")
                try? await Task.sleep(for: .milliseconds(350))
                await refresh()

            case let .voice(active):
                if active {
                    guard !isVoiceAutomationActive else { return }
                    try await automation.setVoiceDictation(active: true)
                    isVoiceAutomationActive = true
                    if isVoicePressed { showFeedback("正在听写…") }
                } else {
                    guard isVoiceAutomationActive else { return }
                    try await automation.setVoiceDictation(active: false)
                    isVoiceAutomationActive = false
                    showFeedback("听写结束")
                }

            case let .openTask(task, index):
                try automation.openTask(id: task.id)
                seen[task.id] = max(task.updatedAt, Int64(Date().timeIntervalSince1970 * 1_000))
                UserDefaults.standard.set(seen, forKey: Keys.seen)
                showFeedback("已打开任务 \(index + 1)")
                await refresh()
            }
        } catch {
            if case .voice(active: true) = request {
                isVoicePressed = false
            }
            if request.isReasoningAdjustment {
                automationQueue.removeAll(where: \AutomationRequest.isReasoningAdjustment)
                pendingReasoningLevel = nil
                pendingReasoningDeadline = .distantPast
                await refresh()
            }
            showFeedback(error.localizedDescription)
        }
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedbackMessage = message
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.feedbackMessage = nil
        }
    }
}
