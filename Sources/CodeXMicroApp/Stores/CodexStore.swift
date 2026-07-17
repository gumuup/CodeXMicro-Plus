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

    @Published var hapticStrength: HapticStrength {
        didSet { UserDefaults.standard.set(hapticStrength.rawValue, forKey: Keys.hapticStrength) }
    }
    @Published var keySoundEnabled: Bool {
        didSet { UserDefaults.standard.set(keySoundEnabled, forKey: Keys.keySound) }
    }

    private enum Keys {
        static let hapticStrength = "hapticStrength"
        static let keySound = "keySoundEnabled"
        static let seen = "seenTasks"
        static let fastMode = "fastModeEnabled"
        static let codexUsageMetric = "codexUsageMetric"
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
    private var pollingTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private let automationQueue = SerialAsyncQueue<AutomationRequest>()
    private var isVoiceAutomationActive = false
    private var seen: [String: Int64]
    private var pendingReasoningLevel: ReasoningLevel?
    private var pendingReasoningDeadline = Date.distantPast

    init(
        stateService: CodexStateService = CodexStateService(),
        automation: CodexAutomationService = CodexAutomationService(),
        haptics: HapticService = HapticService()
    ) {
        self.stateService = stateService
        self.automation = automation
        self.haptics = haptics
        self.hapticStrength = HapticStrength(rawValue: UserDefaults.standard.string(forKey: Keys.hapticStrength) ?? "standard") ?? .standard
        self.keySoundEnabled = UserDefaults.standard.object(forKey: Keys.keySound) as? Bool ?? true
        self.isFastModeEnabled = UserDefaults.standard.bool(forKey: Keys.fastMode)
        self.codexUsageMetric = CodexUsageMetric(
            rawValue: UserDefaults.standard.string(forKey: Keys.codexUsageMetric) ?? ""
        ) ?? .weeklyRemaining
        self.seen = UserDefaults.standard.dictionary(forKey: Keys.seen) as? [String: Int64] ?? [:]
    }

    deinit {
        pollingTask?.cancel()
        feedbackTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }
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

    private func tactilePress() {
        haptics.press(strength: hapticStrength, soundEnabled: keySoundEnabled)
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
