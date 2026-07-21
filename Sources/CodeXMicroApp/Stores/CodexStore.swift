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
    @Published private(set) var isKeyMonitoringActive = false
    @Published private(set) var shortcutRegistrationFailures: [ShortcutTarget: ShortcutService.RegistrationFailure] = [:]
    @Published private(set) var radialMenuItems: [RadialMenuItem]
    @Published private(set) var radialMenuProfiles: [RadialMenuProfile]
    @Published private(set) var selectedRadialMenuProfileID: UUID
    @Published private(set) var radialItemShortcutRegistrationFailures: Set<UUID> = []
    @Published private(set) var radialMenuGlobalModeEnabled: Bool

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
        static let radialMenuItems = "radialMenuItems.v1"
        static let radialMenuProfiles = "radialMenuProfiles.v1"
        static let radialMenuGlobalModeEnabled = "radialMenuGlobalModeEnabled"
    }

    private enum AutomationRequest {
        case micro(MicroAction, successMessage: String?)
        case toolbox(ToolboxAction)
        case radial(RadialMenuItem)
        case joystick(JoystickDirection)
        case voice(active: Bool)
        case openTask(CodexTask, index: Int)

        var isReasoningAdjustment: Bool {
            guard case let .micro(action, _) = self else { return false }
            return action == .reasoningUp || action == .reasoningDown
        }
    }

    private enum VoiceInputSource: Hashable {
        case panel
        case shortcut
    }

    private let stateService: CodexStateService
    let automation: CodexAutomationService
    let haptics: HapticService
    private let shortcutService: ShortcutService
    private let radialItemShortcutService: RadialItemShortcutService
    private var pollingTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var shortcutRecordingTimeoutTask: Task<Void, Never>?
    private let automationQueue = SerialAsyncQueue<AutomationRequest>()
    private var isVoiceAutomationActive = false
    private var activeVoiceInputs: Set<VoiceInputSource> = []
    private var navigationTaskID: String?
    private var seen: [String: Int64]
    private var pendingReasoningLevel: ReasoningLevel?
    private var pendingReasoningDeadline = Date.distantPast
    private var lastKnownAccessibilityTrust = false
    var quickLaunchHandler: (() -> Void)?
    var radialMenuHandler: (() -> Void)?
    var radialMenuReleaseHandler: (() -> Void)?
    var radialMenuPreviewHandler: (([RadialMenuItem]) -> Void)?

    init(
        stateService: CodexStateService = CodexStateService(),
        automation: CodexAutomationService? = nil,
        haptics: HapticService? = nil,
        shortcutService: ShortcutService? = nil,
        radialItemShortcutService: RadialItemShortcutService? = nil
    ) {
        self.stateService = stateService
        self.automation = automation ?? CodexAutomationService()
        self.haptics = haptics ?? HapticService()
        self.shortcutService = shortcutService ?? ShortcutService()
        self.radialItemShortcutService = radialItemShortcutService ?? RadialItemShortcutService()
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
        let installedDefaultsVersion = UserDefaults.standard.integer(forKey: Keys.shortcutDefaultsVersion)
        if var migratedBindings = savedShortcutBindings {
            if installedDefaultsVersion < 1 {
                migratedBindings = ShortcutDefaults.merging(into: migratedBindings)
            }
            if installedDefaultsVersion < 2,
               migratedBindings[.quickLaunch] == nil {
                migratedBindings[.quickLaunch] = ShortcutDefaults.bindings[.quickLaunch]
            }
            if installedDefaultsVersion < 3,
               migratedBindings[.togglePanelPosition] == nil {
                migratedBindings[.togglePanelPosition] = ShortcutDefaults.bindings[.togglePanelPosition]
            }
            if installedDefaultsVersion < 4,
               migratedBindings[.quickLaunch] == ShortcutDefaults.legacyQuickLaunchBinding {
                migratedBindings[.quickLaunch] = ShortcutDefaults.bindings[.quickLaunch]
            }
            if installedDefaultsVersion < 5,
               migratedBindings[.radialMenu] == nil {
                migratedBindings[.radialMenu] = ShortcutDefaults.bindings[.radialMenu]
            }
            self.shortcutBindings = migratedBindings
            if installedDefaultsVersion < ShortcutDefaults.currentVersion,
               let data = try? JSONEncoder().encode(migratedBindings) {
                UserDefaults.standard.set(data, forKey: Keys.shortcutBindings)
                UserDefaults.standard.set(ShortcutDefaults.currentVersion, forKey: Keys.shortcutDefaultsVersion)
            }
        } else {
            self.shortcutBindings = ShortcutDefaults.bindings
            if let data = try? JSONEncoder().encode(ShortcutDefaults.bindings) {
                UserDefaults.standard.set(data, forKey: Keys.shortcutBindings)
                UserDefaults.standard.set(ShortcutDefaults.currentVersion, forKey: Keys.shortcutDefaultsVersion)
            }
        }
        self.shortcutRecordingTarget = nil
        let legacyRadialItems = UserDefaults.standard.data(forKey: Keys.radialMenuItems).flatMap {
            try? JSONDecoder().decode([RadialMenuItem].self, from: $0)
        } ?? RadialMenuDefaults.items
        let savedProfiles = UserDefaults.standard.data(forKey: Keys.radialMenuProfiles).flatMap {
            try? JSONDecoder().decode([RadialMenuProfile].self, from: $0)
        }
        var profiles = savedProfiles?.isEmpty == false
            ? savedProfiles!
            : [RadialMenuDefaults.chatGPTProfile(items: legacyRadialItems)]
        let hadGlobalProfile = profiles.contains(where: \.isGlobal)
        if !hadGlobalProfile {
            profiles.insert(RadialMenuDefaults.globalProfile(), at: 0)
        }
        let storedGlobalModeEnabled = UserDefaults.standard.object(
            forKey: Keys.radialMenuGlobalModeEnabled
        ) as? Bool
        let globalModeEnabled = RadialMenuDefaults.initialGlobalModeEnabled(
            savedProfilesExist: savedProfiles != nil,
            storedValue: storedGlobalModeEnabled
        )
        let selectedProfile = globalModeEnabled
            ? profiles.first(where: \.isGlobal) ?? profiles[0]
            : profiles.first(where: \RadialMenuProfile.isDefault) ?? profiles[0]
        self.radialMenuProfiles = profiles
        self.selectedRadialMenuProfileID = selectedProfile.id
        self.radialMenuItems = selectedProfile.items
        self.radialMenuGlobalModeEnabled = globalModeEnabled
        self.lastKnownAccessibilityTrust = self.automation.isAccessibilityTrusted
        if storedGlobalModeEnabled == nil {
            UserDefaults.standard.set(globalModeEnabled, forKey: Keys.radialMenuGlobalModeEnabled)
        }
        if savedProfiles == nil || !hadGlobalProfile {
            saveRadialMenuProfiles()
        }
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
            onRelease: { [weak self] target in self?.releaseShortcut(target) },
            onCapture: { [weak self] event in self?.handleShortcutCapture(event) }
        )
        radialItemShortcutService.start { [weak self] gesture in
            self?.performRadialItemShortcut(gesture)
        }
        radialItemShortcutRegistrationFailures = radialItemShortcutService.update(profiles: radialMenuProfiles)
        let registrationFailures = updateShortcutRegistrations()
        if let target = ShortcutTarget.allCases.first(where: { registrationFailures[$0] != nil }),
           let binding = shortcutBindings[target], let failure = registrationFailures[target] {
            showFeedback(registrationFailureMessage(failure, binding: binding))
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .milliseconds(1_200))
            }
        }
    }

    func refresh() async {
        refreshDirectKeyMonitoringForPermissionChange()
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

    func perform(_ item: RadialMenuItem) {
        guard item.action != .unconfigured else {
            showFeedback("该轮盘位置尚未配置")
            return
        }
        haptics.radialConfirmation(strength: hapticStrength, soundEnabled: keySoundEnabled)
        enqueueAutomation(.radial(item))
    }

    func addRadialMenuItem() {
        guard radialMenuItems.count < 12 else {
            showFeedback("轮盘最多放置 12 个操作")
            return
        }
        radialMenuItems.append(
            RadialMenuItem(
                title: "新操作",
                systemImage: "plus.circle.fill",
                action: .codexToolbox(.openCodex)
            )
        )
        saveSelectedRadialMenuItems()
    }

    func updateRadialMenuItem(_ item: RadialMenuItem) {
        guard let index = radialMenuItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updatedItem = item
        if let shortcut = updatedItem.triggerShortcut {
            guard !shortcut.modifiers.isEmpty else {
                updatedItem.triggerShortcut = nil
                radialMenuItems[index] = updatedItem
                saveSelectedRadialMenuItems()
                showFeedback("轮盘项快捷键请至少包含一个修饰键")
                return
            }
            if let target = shortcutBindings.first(where: { $0.value.gesture == shortcut.gesture })?.key {
                updatedItem.triggerShortcut = nil
                radialMenuItems[index] = updatedItem
                saveSelectedRadialMenuItems()
                showFeedback("\(shortcut.displayName) 已用于 \(target.title)")
                return
            }
            if let duplicate = radialMenuItems.firstIndex(where: {
                $0.id != item.id && $0.triggerShortcut?.gesture == shortcut.gesture
            }) {
                radialMenuItems[duplicate].triggerShortcut = nil
                showFeedback("\(shortcut.displayName) 已改为触发 \(updatedItem.title)")
            }
        }
        radialMenuItems[index] = updatedItem
        saveSelectedRadialMenuItems()
    }

    func removeRadialMenuItem(id: UUID) {
        guard radialMenuItems.count > 1 else {
            showFeedback("轮盘至少保留一个操作")
            return
        }
        radialMenuItems.removeAll { $0.id == id }
        saveSelectedRadialMenuItems()
    }

    func moveRadialMenuItem(id: UUID, offset: Int) {
        guard let source = radialMenuItems.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(source + offset, 0), radialMenuItems.count - 1)
        guard destination != source else { return }
        let item = radialMenuItems.remove(at: source)
        radialMenuItems.insert(item, at: destination)
        saveSelectedRadialMenuItems()
    }

    func moveRadialMenuItem(id: UUID, relativeTo targetID: UUID, insertAfter: Bool) {
        guard id != targetID,
              let source = radialMenuItems.firstIndex(where: { $0.id == id }) else { return }
        let item = radialMenuItems.remove(at: source)
        guard let target = radialMenuItems.firstIndex(where: { $0.id == targetID }) else {
            radialMenuItems.insert(item, at: min(source, radialMenuItems.count))
            return
        }
        let destination = min(target + (insertAfter ? 1 : 0), radialMenuItems.count)
        radialMenuItems.insert(item, at: destination)
        saveSelectedRadialMenuItems()
        haptics.radialSelectionDetent(strength: hapticStrength)
    }

    func restoreDefaultRadialMenu() {
        if selectedRadialMenuProfile?.isGlobal == true {
            radialMenuItems = RadialMenuDefaults.globalItems
        } else if selectedRadialMenuProfile?.isDefault == true {
            radialMenuItems = RadialMenuDefaults.items
        } else {
            radialMenuItems = RadialMenuDefaults.emptyItems
        }
        saveSelectedRadialMenuItems()
        showFeedback("已恢复 \(selectedRadialMenuProfile?.name ?? "应用") 的默认轮盘")
    }

    func previewRadialMenu() {
        radialMenuPreviewHandler?(radialMenuItems)
    }

    var selectedRadialMenuProfile: RadialMenuProfile? {
        radialMenuProfiles.first { $0.id == selectedRadialMenuProfileID }
    }

    func selectRadialMenuProfile(id: UUID) {
        guard let profile = radialMenuProfiles.first(where: { $0.id == id }) else { return }
        selectedRadialMenuProfileID = profile.id
        radialMenuItems = profile.items
    }

    func setRadialMenuGlobalModeEnabled(_ enabled: Bool) {
        guard radialMenuGlobalModeEnabled != enabled else { return }
        radialMenuGlobalModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.radialMenuGlobalModeEnabled)
        if enabled {
            if let globalProfile = radialMenuProfiles.first(where: \.isGlobal) {
                selectRadialMenuProfile(id: globalProfile.id)
            }
        } else if let defaultProfile = radialMenuProfiles.first(where: \.isDefault) {
            selectRadialMenuProfile(id: defaultProfile.id)
        }
        showFeedback(enabled ? "已开启轮盘全局模式" : "已恢复按应用匹配轮盘")
    }

    @discardableResult
    func addRadialMenuProfile(applicationURL: URL) -> UUID? {
        let bundle = Bundle(url: applicationURL)
        guard let identifier = bundle?.bundleIdentifier, !identifier.isEmpty else {
            showFeedback("无法读取该应用的标识")
            return nil
        }
        if let existing = radialMenuProfiles.first(where: { $0.bundleIdentifier == identifier }) {
            selectRadialMenuProfile(id: existing.id)
            showFeedback("该应用已有轮盘预设")
            return existing.id
        }

        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let profile = RadialMenuProfile(
            name: displayName,
            applicationPath: applicationURL.path,
            bundleIdentifier: identifier,
            items: RadialMenuDefaults.emptyItems
        )
        radialMenuProfiles.append(profile)
        selectedRadialMenuProfileID = profile.id
        radialMenuItems = profile.items
        saveRadialMenuProfiles()
        showFeedback("已添加 \(displayName) 专属轮盘")
        return profile.id
    }

    func removeRadialMenuProfile(id: UUID) {
        guard let profile = radialMenuProfiles.first(where: { $0.id == id }),
              !profile.isDefault, !profile.isGlobal else {
            showFeedback("全局模式和 ChatGPT 默认预设不能删除")
            return
        }
        radialMenuProfiles.removeAll { $0.id == id }
        let fallback = radialMenuProfiles.first(where: \RadialMenuProfile.isDefault) ?? radialMenuProfiles[0]
        selectedRadialMenuProfileID = fallback.id
        radialMenuItems = fallback.items
        saveRadialMenuProfiles()
        showFeedback("已移除 \(profile.name) 预设")
    }

    func radialMenuItemsForFrontmostApplication() -> [RadialMenuItem] {
        RadialMenuProfileResolver.items(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            profiles: radialMenuProfiles,
            globalModeEnabled: radialMenuGlobalModeEnabled
        )
    }

    func isRadialItemShortcutActive(itemID: UUID) -> Bool {
        !radialItemShortcutRegistrationFailures.contains(itemID)
    }

    func setRadialItemShortcutRecording(_ active: Bool) {
        radialItemShortcutService.setSuspended(active)
        if !active {
            radialItemShortcutRegistrationFailures = radialItemShortcutService.update(profiles: radialMenuProfiles)
        }
    }

    private func performRadialItemShortcut(_ gesture: ShortcutGesture) {
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let profile = RadialMenuProfileResolver.profile(
            for: identifier,
            profiles: radialMenuProfiles,
            globalModeEnabled: radialMenuGlobalModeEnabled
        )
        guard let item = profile?.items.first(where: { $0.triggerShortcut?.gesture == gesture }) else {
            return
        }
        perform(item)
    }

    func beginVoice() {
        beginVoice(from: .panel)
    }

    func endVoice() {
        endVoice(from: .panel)
    }

    func toggleVoice() {
        if activeVoiceInputs.contains(.panel) {
            endVoice(from: .panel)
        } else {
            beginVoice(from: .panel)
        }
    }

    private func beginVoice(from source: VoiceInputSource) {
        guard activeVoiceInputs.insert(source).inserted else { return }
        guard activeVoiceInputs.count == 1 else { return }
        isVoicePressed = true
        tactilePress()
        enqueueAutomation(.voice(active: true))
    }

    private func endVoice(from source: VoiceInputSource) {
        guard activeVoiceInputs.remove(source) != nil else { return }
        guard activeVoiceInputs.isEmpty else { return }
        isVoicePressed = false
        haptics.press(strength: hapticStrength, soundEnabled: false)
        enqueueAutomation(.voice(active: false))
    }

    func performJoystick(_ direction: JoystickDirection) {
        if direction == .left || direction == .right {
            navigateTask(direction)
            return
        }
        enqueueAutomation(.joystick(direction))
    }

    private func navigateTask(_ direction: JoystickDirection) {
        guard let index = CodexTaskNavigator.targetIndex(
            taskIDs: tasks.map(\.id),
            currentTaskID: navigationTaskID,
            direction: direction
        ), let task = task(at: index) else {
            showFeedback("暂无可切换的任务")
            return
        }
        tactilePress()
        enqueueAutomation(.openTask(task, index: index))
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

    func radialMenuAppeared() {
        haptics.radialReveal(strength: hapticStrength)
    }

    func radialSelectionDetent() {
        haptics.radialSelectionDetent(strength: hapticStrength)
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

    func retryShortcutMonitoring(for requestedTarget: ShortcutTarget? = nil) {
        let failures = updateShortcutRegistrations()
        if let requestedTarget, let binding = shortcutBindings[requestedTarget] {
            if let failure = failures[requestedTarget] {
                showFeedback(registrationFailureMessage(failure, binding: binding))
            } else {
                showFeedback("\(binding.displayName) 未发现 macOS 系统快捷键冲突")
            }
            return
        }
        if let target = ShortcutTarget.allCases.first(where: { failures[$0] != nil }),
           let failure = failures[target], let binding = shortcutBindings[target] {
            showFeedback(registrationFailureMessage(failure, binding: binding))
        }
    }

    func shortcut(for target: ShortcutTarget) -> KeyboardShortcutBinding? {
        shortcutBindings[target]
    }

    func isShortcutActive(_ target: ShortcutTarget) -> Bool {
        shortcutService.isActive(target)
    }

    var hasKeyBindings: Bool {
        !shortcutBindings.isEmpty
    }

    func shortcutRegistrationIssue(for target: ShortcutTarget) -> String? {
        guard let failure = shortcutRegistrationFailures[target] else {
            return nil
        }
        return switch failure {
        case .duplicateBinding:
            "与另一个功能重复"
        case .shadowedByPhysicalMapping:
            "被一级物理按键映射覆盖"
        case .systemHotKeyConflict:
            "与 macOS 系统快捷键冲突"
        case .hotKeyRegistrationUnavailable:
            "系统热键注册失败"
        case .accessibilityRequired:
            "等待辅助功能授权后接管该按键"
        case .directMonitorUnavailable:
            "物理按键映射启动失败"
        }
    }

    func beginShortcutRecording(for target: ShortcutTarget) {
        shortcutRecordingTimeoutTask?.cancel()
        shortcutRecordingTarget = target
        shortcutService.beginRecording(for: target)
        showFeedback("为 \(target.title) 轻点任意单键，或按下组合键 · 修饰键请单独轻点")
        shortcutRecordingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, self?.shortcutRecordingTarget == target else { return }
            self?.cancelShortcutRecording(message: "按键映射设置已超时")
        }
    }

    func cancelShortcutRecording() {
        cancelShortcutRecording(message: "已取消按键映射设置")
    }

    func clearShortcut(for target: ShortcutTarget) {
        shortcutBindings.removeValue(forKey: target)
        if shortcutRecordingTarget == target {
            shortcutRecordingTarget = nil
            shortcutService.cancelRecording()
        }
        persistShortcuts()
        showFeedback("已清除 \(target.title) 的按键映射")
    }

    func restoreDefaultShortcut(for target: ShortcutTarget) {
        guard let defaultBinding = ShortcutDefaults.bindings[target] else { return }
        if shortcutRecordingTarget == target {
            shortcutRecordingTarget = nil
            shortcutService.cancelRecording()
        }
        let previousBindings = shortcutBindings
        shortcutBindings[target] = defaultBinding
        let failures = updateShortcutRegistrations()
        if let failure = failures[target] {
            if failure.preventsSaving {
                shortcutBindings = previousBindings
                _ = updateShortcutRegistrations()
                showFeedback(registrationFailureMessage(failure, binding: defaultBinding))
                return
            }
            showFeedback(registrationFailureMessage(failure, binding: defaultBinding))
        } else {
            showFeedback("\(target.title) 已恢复为 \(defaultBinding.displayName)")
        }
        saveShortcutBindings()
    }

    private func tactilePress() {
        haptics.press(strength: hapticStrength, soundEnabled: keySoundEnabled)
    }

    private func triggerShortcut(_ target: ShortcutTarget) {
        switch target {
        case .quickLaunch:
            if panelPosition == .bottom {
                panelPosition = .top
            }
            quickLaunchHandler?()
        case .radialMenu: radialMenuHandler?()
        case .togglePanelPosition:
            panelPosition = panelPosition == .top ? .bottom : .top
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
            beginVoice(from: .shortcut)
        case .codexStatus: activateCodexStatusButton()
        case .reasoningDown: adjustReasoning(by: -1)
        case .reasoningUp: adjustReasoning(by: 1)
        }
    }

    private func releaseShortcut(_ target: ShortcutTarget) {
        switch target {
        case .radialMenu:
            radialMenuReleaseHandler?()
        case .voice:
            endVoice(from: .shortcut)
        default:
            break
        }
    }

    private func handleShortcutCapture(_ event: ShortcutService.CaptureEvent) {
        switch event {
        case let .captured(target, binding):
            shortcutRecordingTimeoutTask?.cancel()
            guard ![ShortcutTarget.quickLaunch, .radialMenu].contains(target) || !binding.modifiers.isEmpty else {
                shortcutRecordingTarget = nil
                _ = updateShortcutRegistrations()
                showFeedback("系统级启动快捷键请至少包含 Control、Option、Shift 或 Command")
                return
            }
            let previousBindings = shortcutBindings
            let reassignedTarget = shortcutBindings.first(where: {
                $0.key != target && $0.value.gesture == binding.gesture
            })?.key
            if let reassignedTarget {
                if target == .quickLaunch || target == .radialMenu {
                    shortcutRecordingTarget = nil
                    _ = updateShortcutRegistrations()
                    showFeedback("\(binding.displayName) 已用于 \(reassignedTarget.title)，请设置其他按键")
                    return
                }
                shortcutBindings.removeValue(forKey: reassignedTarget)
            }
            shortcutBindings[target] = binding
            shortcutRecordingTarget = nil
            let registrationFailures = updateShortcutRegistrations()
            if let failure = registrationFailures[target], failure.preventsSaving {
                shortcutBindings = previousBindings
                _ = updateShortcutRegistrations()
                showFeedback(registrationFailureMessage(failure, binding: binding))
                return
            }
            saveShortcutBindings()
            if let failure = registrationFailures[target] {
                showFeedback(registrationFailureMessage(failure, binding: binding))
                if failure == .accessibilityRequired { automation.requestAccessibility() }
                return
            }
            let shadowedCount = registrationFailures.values.filter {
                $0 == .shadowedByPhysicalMapping
            }.count
            let shadowedSuffix = shadowedCount > 0 ? " · 已覆盖 \(shadowedCount) 个组合" : ""
            let reassignedSuffix = reassignedTarget.map { " · 已从 \($0.title) 改绑" } ?? ""
            showFeedback("\(target.title)：\(binding.displayName) · \(binding.activationMode.label)\(reassignedSuffix)\(shadowedSuffix)")
        case .cancelled:
            shortcutRecordingTimeoutTask?.cancel()
            shortcutRecordingTarget = nil
            _ = updateShortcutRegistrations()
            if feedbackMessage?.contains("超时") != true {
                showFeedback("已取消按键映射设置")
            }
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
    private func persistShortcuts() -> [ShortcutTarget: ShortcutService.RegistrationFailure] {
        let failures = updateShortcutRegistrations()
        saveShortcutBindings()
        return failures
    }

    private func saveShortcutBindings() {
        guard let data = try? JSONEncoder().encode(shortcutBindings) else { return }
        UserDefaults.standard.set(data, forKey: Keys.shortcutBindings)
    }

    private func updateShortcutRegistrations() -> [ShortcutTarget: ShortcutService.RegistrationFailure] {
        let failures = shortcutService.update(bindings: shortcutBindings)
        shortcutRegistrationFailures = failures
        isKeyMonitoringActive = shortcutService.isKeyMonitoringActive
        lastKnownAccessibilityTrust = automation.isAccessibilityTrusted
        return failures
    }

    private func refreshDirectKeyMonitoringForPermissionChange() {
        let isTrusted = automation.isAccessibilityTrusted
        guard isTrusted != lastKnownAccessibilityTrust else {
            isKeyMonitoringActive = shortcutService.isKeyMonitoringActive
            return
        }
        lastKnownAccessibilityTrust = isTrusted
        _ = updateShortcutRegistrations()
    }

    private func registrationFailureMessage(
        _ failure: ShortcutService.RegistrationFailure,
        binding: KeyboardShortcutBinding
    ) -> String {
        switch failure {
        case .duplicateBinding:
            "\(binding.displayName) 已绑定到其他功能，请先改绑或清除"
        case .shadowedByPhysicalMapping:
            "\(binding.displayName) 被一级物理按键映射接管，已保留原设置"
        case .systemHotKeyConflict:
            "\(binding.displayName) 已保存，但与 macOS 系统快捷键重合，当前不会接管"
        case .hotKeyRegistrationUnavailable:
            "无法向 macOS 注册 \(binding.displayName)，请设置其他快捷键后重试"
        case .accessibilityRequired:
            "\(binding.displayName) 已保存；开启辅助功能权限后即可接管该按键"
        case .directMonitorUnavailable:
            "\(binding.displayName) 已保存，但按键映射启动失败；请重新开启辅助功能权限"
        }
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

            case let .radial(item):
                try await automation.perform(item.action)
                showFeedback(item.title)
                if case .codexToolbox = item.action {
                    try? await Task.sleep(for: .milliseconds(350))
                    await refresh()
                }

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
                navigationTaskID = task.id
                seen[task.id] = max(task.updatedAt, Int64(Date().timeIntervalSince1970 * 1_000))
                UserDefaults.standard.set(seen, forKey: Keys.seen)
                showFeedback("已打开任务 \(index + 1)")
                await refresh()
            }
        } catch {
            if case .voice(active: true) = request {
                activeVoiceInputs.removeAll()
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

    private func saveSelectedRadialMenuItems() {
        guard let index = radialMenuProfiles.firstIndex(where: { $0.id == selectedRadialMenuProfileID }) else {
            return
        }
        radialMenuProfiles[index].items = radialMenuItems
        saveRadialMenuProfiles()
    }

    private func saveRadialMenuProfiles() {
        guard let data = try? JSONEncoder().encode(radialMenuProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Keys.radialMenuProfiles)
        radialItemShortcutRegistrationFailures = radialItemShortcutService.update(profiles: radialMenuProfiles)
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
