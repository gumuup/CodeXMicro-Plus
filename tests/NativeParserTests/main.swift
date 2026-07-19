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
precondition(reasoningDownMenu.items.map(\.title) == ["设置降低推理强度快捷键…", "", "当前：⌃L", "清除降低推理强度快捷键"])
let configureDownItem = reasoningDownMenu.item(at: 0)!
let clearDownItem = reasoningDownMenu.item(at: 3)!
precondition(NSApplication.shared.sendAction(configureDownItem.action!, to: configureDownItem.target, from: configureDownItem))
precondition(NSApplication.shared.sendAction(clearDownItem.action!, to: clearDownItem.target, from: clearDownItem))
precondition(configuredReasoningStep == -1)
precondition(clearedReasoningStep == -1)
let reasoningUpMenu = dialEventView.shortcutMenu(for: 1)
precondition(reasoningUpMenu.items.map(\.title) == ["设置提高推理强度快捷键…"])
let configureUpItem = reasoningUpMenu.item(at: 0)!
precondition(NSApplication.shared.sendAction(configureUpItem.action!, to: configureUpItem.target, from: configureUpItem))
precondition(configuredReasoningStep == 1)

let fastShortcut = KeyboardShortcutBinding(
    keyCode: 3,
    modifiers: [.control, .shift],
    keyLabel: "F"
)
precondition(fastShortcut.displayName == "⌃⇧F")
let shortcutPayload: [ShortcutTarget: KeyboardShortcutBinding] = [.fast: fastShortcut]
let shortcutData = try JSONEncoder().encode(shortcutPayload)
let decodedShortcutPayload = try JSONDecoder().decode(
    [ShortcutTarget: KeyboardShortcutBinding].self,
    from: shortcutData
)
precondition(decodedShortcutPayload == shortcutPayload)
precondition(ShortcutTarget.agent(at: 0) == .agent1)
precondition(ShortcutTarget.agent(at: 5) == .agent6)
precondition(ShortcutTarget.agent(at: 6) == nil)
precondition(ShortcutTarget.allCases.count == 19)
precondition(ShortcutDefaults.bindings.count == ShortcutTarget.allCases.count)
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

let customFastShortcut = KeyboardShortcutBinding(keyCode: 3, modifiers: [.command], keyLabel: "F")
let migratedShortcutBindings = ShortcutDefaults.merging(into: [.fast: customFastShortcut])
precondition(migratedShortcutBindings[.fast] == customFastShortcut)
precondition(migratedShortcutBindings[.agent1] == ShortcutDefaults.bindings[.agent1])

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
