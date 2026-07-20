import Foundation
import AppKit

func lines(_ values: String...) -> Data {
    Data(values.joined(separator: "\n").utf8)
}

let active = lines(
    #"{"timestamp":"2026-07-17T08:00:00.123Z","type":"event_msg","payload":{"type":"task_started"}}"#,
    #"{"timestamp":"2026-07-17T08:00:10.123Z","type":"response_item","payload":{"content":"tool name request_user_input appears in documentation only"}}"#
)
precondition(CodexRolloutParser.status(from: active, seenAt: 0) == .active)

let waiting = lines(
    #"{"timestamp":"2026-07-17T08:00:00.123Z","type":"event_msg","payload":{"type":"task_started"}}"#,
    #"{"timestamp":"2026-07-17T08:01:00.123Z","type":"response_item","payload":{"name":"request_user_input"}}"#
)
precondition(CodexRolloutParser.status(from: waiting, seenAt: 0) == .waiting)

let completed = lines(
    #"{"timestamp":"2026-07-17T08:00:00.123Z","type":"event_msg","payload":{"type":"task_started"}}"#,
    #"{"timestamp":"2026-07-17T08:02:00.123Z","type":"event_msg","payload":{"type":"task_complete"}}"#
)
precondition(CodexRolloutParser.status(from: completed, seenAt: 0) == .complete)
precondition(CodexRolloutParser.status(from: completed, seenAt: 1_784_275_321_000) == .idle)

let reasoning = lines(
    #"{"payload":{"thread_settings":{"reasoning_effort":"low"}}}"#,
    #"{"payload":{"thread_settings":{"reasoning_effort":"high"}}}"#
)
precondition(CodexRolloutParser.reasoningLevel(from: reasoning) == .high)

let weeklyQuota = lines(
    #"{"timestamp":"2026-07-17T08:00:00.123Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1784682204}}}}"#
)
let parsedQuota = CodexRolloutParser.weeklyQuota(from: weeklyQuota)
precondition(parsedQuota?.remainingPercent == 68)
precondition(parsedQuota?.resetsAt?.timeIntervalSince1970 == 1_784_682_204)

let mixedQuotaLimits = lines(
    #"{"timestamp":"2026-07-17T08:00:00.123Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":23.0,"window_minutes":10080,"resets_at":1784682204}}}}"#,
    #"{"timestamp":"2026-07-17T08:01:00.123Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1784682304}}}}"#
)
precondition(CodexRolloutParser.weeklyQuota(from: mixedQuotaLimits)?.remainingPercent == 77)

let liveQuotaResponse = lines(
    #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":59,"windowDurationMins":10080,"resetsAt":1784781374}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":59,"windowDurationMins":10080,"resetsAt":1784781374}}}}}"#
)
let liveQuota = CodexRolloutParser.liveWeeklyQuota(
    from: liveQuotaResponse,
    observedAt: Date(timeIntervalSince1970: 1_784_264_800)
)
precondition(liveQuota?.remainingPercent == 41)
precondition(liveQuota?.observedAt == 1_784_264_800_000)

let liveUsageResponse = lines(
    #"{"id":3,"result":{"summary":{"lifetimeTokens":7694763639}}}"#
)
precondition(CodexRolloutParser.liveLifetimeTokens(from: liveUsageResponse) == 7_694_763_639)
precondition(TokenCountFormatter.compact(7_694_763_639) == "76.9亿")
precondition(TokenCountFormatter.full(7_694_763_639).replacingOccurrences(of: ",", with: "") == "7694763639")

let largeProcessOutput = ProcessOutputReader.run(
    executableURL: URL(fileURLWithPath: "/usr/bin/jot"),
    arguments: ["-b", "x", "70000"]
)
precondition(largeProcessOutput?.status == 0)
precondition(largeProcessOutput?.data.count == 140_000)

precondition(DialStepResolver.tapStep(at: 19, width: 76) == -1)
precondition(DialStepResolver.tapStep(at: 57, width: 76) == 1)
precondition(DialStepResolver.dragSteps(from: 0, to: 2) == [1, 1])
precondition(DialStepResolver.dragSteps(from: 1, to: -2) == [-1, -1, -1])
precondition(ReasoningLevel.allCases.map(\.label) == ["轻度", "中", "高", "极高"])
precondition(ReasoningLevel.allCases.map(\.dialAngleDegrees) == [-90, 0, 90, 180])
let dialEventView = DialEventView()
dialEventView.shortcutName = { $0 < 0 ? "⌃L" : nil }
var configuredReasoningStep: Int?
var clearedReasoningStep: Int?
dialEventView.onConfigureShortcut = { configuredReasoningStep = $0 }
dialEventView.onClearShortcut = { clearedReasoningStep = $0 }
let reasoningDownMenu = dialEventView.shortcutMenu(for: -1)
precondition(reasoningDownMenu.items.map(\.title) == ["设置降低推理强度按键映射…", "", "当前：⌃L", "清除降低推理强度按键映射"])
let configureDownItem = reasoningDownMenu.item(at: 0)!
let clearDownItem = reasoningDownMenu.item(at: 3)!
precondition(NSApplication.shared.sendAction(configureDownItem.action!, to: configureDownItem.target, from: configureDownItem))
precondition(NSApplication.shared.sendAction(clearDownItem.action!, to: clearDownItem.target, from: clearDownItem))
precondition(configuredReasoningStep == -1)
precondition(clearedReasoningStep == -1)
let reasoningUpMenu = dialEventView.shortcutMenu(for: 1)
precondition(reasoningUpMenu.items.map(\.title) == ["设置提高推理强度按键映射…"])
let configureUpItem = reasoningUpMenu.item(at: 0)!
precondition(NSApplication.shared.sendAction(configureUpItem.action!, to: configureUpItem.target, from: configureUpItem))
precondition(configuredReasoningStep == 1)

let fastShortcut = KeyboardShortcutBinding(
    keyCode: 3,
    modifiers: [.control, .shift],
    keyLabel: "F"
)
precondition(fastShortcut.displayName == "⌃⇧F")
precondition(fastShortcut.activationMode == .registeredHotKey)
let shortcutPayload: [ShortcutTarget: KeyboardShortcutBinding] = [.fast: fastShortcut]
let shortcutData = try JSONEncoder().encode(shortcutPayload)
let decodedShortcutPayload = try JSONDecoder().decode(
    [ShortcutTarget: KeyboardShortcutBinding].self,
    from: shortcutData
)
precondition(decodedShortcutPayload == shortcutPayload)
let legacyShortcutData = Data(#"["fast",{"keyCode":3,"keyLabel":"F","modifiers":10}]"#.utf8)
let legacyShortcutPayload = try JSONDecoder().decode(
    [ShortcutTarget: KeyboardShortcutBinding].self,
    from: legacyShortcutData
)
precondition(legacyShortcutPayload[.fast] == fastShortcut)
precondition(ShortcutTarget.agent(at: 0) == .agent1)
precondition(ShortcutTarget.agent(at: 5) == .agent6)
precondition(ShortcutTarget.agent(at: 6) == nil)
precondition(ShortcutTarget.allCases.count == 19)
precondition(ShortcutDefaults.bindings.count == ShortcutTarget.allCases.count)
precondition(CodexKeybindingResolver.parse("Ctrl+F")?.displayName == "⌃F")
precondition(CodexKeybindingResolver.parse("Ctrl+Shift+D")?.displayName == "⌃⇧D")
precondition(CodexKeybindingResolver.parse("Ctrl+=")?.keyCode == 24)
precondition(CodexKeybindingResolver.parse("Ctrl+-")?.keyCode == 27)
precondition(CodexKeybindingResolver.parse("Cmd+Shift+Left")?.displayName == "⇧⌘←")
precondition(CodexKeybindingResolver.parse("Ctrl+Unknown") == nil)
precondition(Set(ShortcutDefaults.bindings.values).count == ShortcutDefaults.bindings.count)
precondition(ShortcutDefaults.bindings[.fast]?.displayName == "⌃F")
precondition(ShortcutDefaults.bindings[.approve]?.displayName == "⌃[")
precondition(ShortcutDefaults.bindings[.decline]?.displayName == "⌃]")
precondition(ShortcutDefaults.bindings[.reasoningDown]?.displayName == "⌃-")
precondition(ShortcutDefaults.bindings[.reasoningUp]?.displayName == "⌃=")
precondition(ShortcutDefaults.bindings[.newTask]?.displayName == "⌃N")
precondition(ShortcutDefaults.bindings[.voice]?.displayName == "⌃⇧D")
precondition(ShortcutDefaults.bindings[.toggleLabels]?.displayName == "⌃H")
precondition(ShortcutDefaults.bindings[.codexStatus]?.displayName == "⌃C")
precondition(ShortcutDefaults.bindings[.joystickUp]?.displayName == "⌃W")
precondition(ShortcutDefaults.bindings[.joystickDown]?.displayName == "⌃S")
precondition(ShortcutDefaults.bindings[.joystickLeft]?.displayName == "⌃A")
precondition(ShortcutDefaults.bindings[.joystickRight]?.displayName == "⌃D")
precondition((1...6).map { ShortcutDefaults.bindings[ShortcutTarget.agent(at: $0 - 1)!]?.displayName } == (1...6).map { "⌃\($0)" })

let navigationTaskIDs = ["task-1", "task-2", "task-3"]
precondition(CodexTaskNavigator.targetIndex(taskIDs: navigationTaskIDs, currentTaskID: nil, direction: .right) == 1)
precondition(CodexTaskNavigator.targetIndex(taskIDs: navigationTaskIDs, currentTaskID: nil, direction: .left) == 2)
precondition(CodexTaskNavigator.targetIndex(taskIDs: navigationTaskIDs, currentTaskID: "task-2", direction: .right) == 2)
precondition(CodexTaskNavigator.targetIndex(taskIDs: navigationTaskIDs, currentTaskID: "task-1", direction: .left) == 2)
precondition(CodexTaskNavigator.targetIndex(taskIDs: navigationTaskIDs, currentTaskID: "missing", direction: .right) == 1)
precondition(CodexTaskNavigator.targetIndex(taskIDs: [], currentTaskID: nil, direction: .left) == nil)
precondition(CodexTaskNavigator.targetIndex(taskIDs: navigationTaskIDs, currentTaskID: nil, direction: .up) == nil)

let customFastShortcut = KeyboardShortcutBinding(keyCode: 3, modifiers: [.command], keyLabel: "F")
let migratedShortcutBindings = ShortcutDefaults.merging(into: [.fast: customFastShortcut])
precondition(migratedShortcutBindings[.fast] == customFastShortcut)
precondition(migratedShortcutBindings[.agent1] == ShortcutDefaults.bindings[.agent1])

let homeShortcut = KeyboardShortcutBinding(keyCode: 115, modifiers: [], keyLabel: "Home")
precondition(homeShortcut.displayName == "Home")
precondition(homeShortcut.activationMode == .directKey)
precondition(homeShortcut.activationMode.label == "物理按键映射 · 一级")
precondition(fastShortcut.activationMode.label == "组合按键映射 · 一级监听")
precondition(ShortcutKeyCatalog.label(for: 115) == "Home")
precondition(ShortcutKeyCatalog.label(for: 82) == "Num 0")
precondition(ShortcutKeyCatalog.label(for: 0) == "A")
precondition(ShortcutKeyCatalog.label(for: 56) == "左 Shift")

let letterMapping = KeyboardShortcutBinding(keyCode: 0, modifiers: [], keyLabel: "A")
precondition(letterMapping.activationMode == .directKey)

var modifierKeyState = PhysicalModifierKeyState()
precondition(modifierKeyState.update(keyCode: 56, eventFlagsRawValue: 1 << 17) == .down)
modifierKeyState.setMappedKeySuppressed(true, keyCode: 56)
precondition(modifierKeyState.modifierFlagsToStripRawValue == 1 << 17)
precondition(modifierKeyState.update(keyCode: 60, eventFlagsRawValue: 1 << 17) == .down)
precondition(modifierKeyState.modifierFlagsToStripRawValue == 0)
precondition(modifierKeyState.update(keyCode: 60, eventFlagsRawValue: 1 << 17) == .up)
precondition(modifierKeyState.modifierFlagsToStripRawValue == 1 << 17)
precondition(modifierKeyState.update(keyCode: 56, eventFlagsRawValue: 0) == .up)
precondition(modifierKeyState.modifierFlagsToStripRawValue == 0)

let localizedHomeShortcut = KeyboardShortcutBinding(keyCode: 115, modifiers: [], keyLabel: "首页")
precondition(localizedHomeShortcut != homeShortcut)
precondition(localizedHomeShortcut.gesture == homeShortcut.gesture)

var directKeyMatcher = DirectKeyEventMatcher()
let directTargets: [UInt16: ShortcutTarget] = [115: .voice]
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .down,
    isRepeat: true,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .suppress)
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .suppress)
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .trigger(.voice))
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .down,
    isRepeat: true,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .suppress)
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .release(.voice))
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .passThrough)

var combinationMatcher = CombinationKeyEventMatcher()
let controlF = ShortcutGesture(keyCode: 3, modifiers: .control)
let combinationTargets: [ShortcutGesture: ShortcutTarget] = [controlF: .fast]
precondition(combinationMatcher.handle(
    keyCode: 3,
    modifiers: .control,
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByGesture: combinationTargets
) == .trigger(.fast))
precondition(combinationMatcher.handle(
    keyCode: 3,
    modifiers: .control,
    phase: .down,
    isRepeat: true,
    isSynthetic: false,
    targetsByGesture: combinationTargets
) == .suppress)
precondition(combinationMatcher.handle(
    keyCode: 3,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByGesture: combinationTargets
) == .release(.fast))
precondition(combinationMatcher.handle(
    keyCode: 3,
    modifiers: .shift,
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByGesture: combinationTargets
) == .passThrough)
precondition(combinationMatcher.handle(
    keyCode: 3,
    modifiers: .control,
    phase: .down,
    isRepeat: false,
    isSynthetic: true,
    targetsByGesture: combinationTargets
) == .passThrough)
precondition(combinationMatcher.handle(
    keyCode: 3,
    modifiers: .control,
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByGesture: combinationTargets
) == .trigger(.fast))
precondition(combinationMatcher.drainTargets() == [.fast])
let modifierTargets: [UInt16: ShortcutTarget] = [56: .voice]
precondition(directKeyMatcher.handle(
    keyCode: 56,
    modifiers: [],
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: modifierTargets
) == .trigger(.voice))
precondition(directKeyMatcher.handle(
    keyCode: 56,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: modifierTargets
) == .release(.voice))
let letterTargets: [UInt16: ShortcutTarget] = [0: .fast]
precondition(directKeyMatcher.handle(
    keyCode: 0,
    modifiers: [],
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: letterTargets
) == .trigger(.fast))
precondition(directKeyMatcher.handle(
    keyCode: 0,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: letterTargets
) == .release(.fast))
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [.shift],
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .trigger(.voice))
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [.shift],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .release(.voice))
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .down,
    isRepeat: false,
    isSynthetic: true,
    targetsByKeyCode: directTargets
) == .passThrough)
precondition(directKeyMatcher.handle(
    keyCode: 119,
    modifiers: [],
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .passThrough)
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .down,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .trigger(.voice))
precondition(directKeyMatcher.drainTargets() == [.voice])
precondition(directKeyMatcher.handle(
    keyCode: 115,
    modifiers: [],
    phase: .up,
    isRepeat: false,
    isSynthetic: false,
    targetsByKeyCode: directTargets
) == .passThrough)

let initialPanelFrame = NSRect(x: 100, y: 200, width: 438, height: 438)
let enlargedTopLeftFrame = PanelResizeCorner.topLeft.frame(size: 500, anchoredTo: initialPanelFrame)
precondition(enlargedTopLeftFrame.maxX == initialPanelFrame.maxX)
precondition(enlargedTopLeftFrame.minY == initialPanelFrame.minY)
let enlargedBottomRightFrame = PanelResizeCorner.bottomRight.frame(size: 500, anchoredTo: initialPanelFrame)
precondition(enlargedBottomRightFrame.minX == initialPanelFrame.minX)
precondition(enlargedBottomRightFrame.maxY == initialPanelFrame.maxY)
precondition(PanelResizeCorner.topRight.sizeDelta(from: .zero, to: NSPoint(x: 20, y: 20)) == 20)
precondition(PanelResizeCorner.bottomLeft.sizeDelta(from: .zero, to: NSPoint(x: -20, y: -20)) == 20)
let resizeHandle = PanelResizeHandleView(corner: .bottomRight)
resizeHandle.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
resizeHandle.updateTrackingAreas()
precondition(resizeHandle.trackingAreas.contains { $0.options.contains(.activeAlways) })
precondition(resizeHandle.trackingAreas.contains { $0.options.contains(.cursorUpdate) })

precondition(ToolboxAction.allCases.count == 52)
precondition(ToolboxAction.fast.microAction == .fast)
precondition(ToolboxAction.createPullRequest.kind == .shortcut)
precondition(ToolboxAction.reviewPullRequest.workflowPrompt != nil)
precondition(ToolboxAction.openAIDocs.kind == .destination)
precondition(ToolboxAction.allCases.filter { $0.category == .git }.count == 7)
let prSearchResults = ToolboxAction.allCases.filter { $0.searchText.contains("pr") }.map(\.title)
precondition(prSearchResults.contains("创建 PR"))
precondition(prSearchResults.contains("审查 PR"))

print("Codex rollout parser, shortcuts, process output, dial interaction, panel resize, and toolbox catalog: PASS")
