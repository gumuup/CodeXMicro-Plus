import SwiftUI

struct MicroPadView: View {
    let store: CodexStore
    let closePanel: () -> Void

    private let designSize: CGFloat = 438

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / designSize

            MicroPadSurface(store: store, closePanel: closePanel)
                .environment(\.microLayoutScale, scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.clear)
    }
}

private struct MicroPadSurface: View {
    @ObservedObject var store: CodexStore
    let closePanel: () -> Void

    @Environment(\.microLayoutScale) private var layoutScale

    @State private var isToolboxPresented = false
    @State private var hoveredCommand: MicroAction?

    private var keySize: CGFloat { scaled(76) }
    private var spacing: CGFloat { scaled(10) }
    private var designSize: CGFloat { scaled(438) }

    var body: some View {
        panelContent
    }

    private var panelContent: some View {
        ZStack {
            enclosure

            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    JoystickView(onTrigger: store.performJoystick, onDetent: store.joystickDetent)
                        .contextMenu { joystickShortcutMenu }
                    AgentKeyView(index: 0, task: store.task(at: 0), labelsVisible: store.labelsVisible) { store.openTask(at: 0) }
                        .shortcutConfigurable(.agent1, store: store)
                    AgentKeyView(index: 1, task: store.task(at: 1), labelsVisible: store.labelsVisible) { store.openTask(at: 1) }
                        .shortcutConfigurable(.agent2, store: store)
                    ReasoningDialView(
                        level: store.reasoningLevel,
                        onAdjust: store.adjustReasoning,
                        shortcutName: { step in
                            let target = reasoningShortcutTarget(for: step)
                            return store.shortcut(for: target).map {
                                let issue = store.shortcutRegistrationIssue(for: target)
                                return "\($0.displayName) · \($0.activationMode.label)"
                                    + (issue.map { " · ⚠︎ \($0)" } ?? "")
                            }
                        },
                        onConfigureShortcut: { step in
                            store.beginShortcutRecording(for: reasoningShortcutTarget(for: step))
                        },
                        onClearShortcut: { step in
                            store.clearShortcut(for: reasoningShortcutTarget(for: step))
                        }
                    )
                }
                .frame(height: keySize)

                HStack(spacing: spacing) {
                    ForEach(2..<6, id: \.self) { index in
                        AgentKeyView(index: index, task: store.task(at: index), labelsVisible: store.labelsVisible) { store.openTask(at: index) }
                            .shortcutConfigurable(ShortcutTarget.agent(at: index)!, store: store)
                    }
                }
                .frame(height: keySize)

                HStack(spacing: spacing) {
                    commandKey(.fast, icon: "bolt.fill", title: "FAST")
                    commandKey(.approve, icon: "checkmark.circle", title: "同意")
                    commandKey(.decline, icon: "xmark.circle", title: "拒绝")
                    commandKey(.newTask, icon: "arrow.up.right.square", title: "新任务")
                }
                .frame(height: keySize)

                HStack(spacing: spacing) {
                    toolboxSensor
                        .frame(width: keySize, height: keySize)
                    VoiceKeyView(
                        isActive: store.isVoicePressed,
                        labelsVisible: store.labelsVisible,
                        onToggle: store.toggleVoice
                    )
                    .frame(width: keySize * 2 + spacing, height: keySize)
                    .shortcutConfigurable(.voice, store: store)
                    Button { store.activateCodexStatusButton() } label: {
                        codexStatusGlyph
                    }
                        .buttonStyle(MechanicalKeyStyle(glow: .indigo))
                        .frame(width: keySize, height: keySize)
                        .help(codexStatusHelp)
                        .accessibilityLabel(codexStatusHelp)
                        .shortcutConfigurable(.codexStatus, store: store)
                }
                .frame(height: keySize)
            }
            .frame(width: keySize * 4 + spacing * 3)
            .offset(y: -scaled(1))

            sideLabels
            moveHandles
            screwHeads
            chromeControls
            feedbackToast
        }
        .frame(width: designSize, height: designSize)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: scaled(68), style: .continuous))
        .overlay { resizeHandles }
    }

    private var moveHandles: some View {
        let cornerExtent = scaled(34)
        let edgeLength = designSize - cornerExtent * 2

        return ZStack {
            VStack(spacing: 0) {
                PanelDragRegion()
                    .frame(width: edgeLength, height: cornerExtent)
                Spacer(minLength: 0)
                PanelDragRegion()
                    .frame(width: edgeLength, height: cornerExtent)
            }

            HStack(spacing: 0) {
                PanelDragRegion()
                    .frame(width: cornerExtent, height: edgeLength)
                Spacer(minLength: 0)
                PanelDragRegion()
                    .frame(width: cornerExtent, height: edgeLength)
            }
        }
        .frame(width: designSize, height: designSize)
    }

    private var resizeHandles: some View {
        VStack {
            HStack {
                PanelResizeHandle(corner: .topLeft)
                    .frame(width: scaled(34), height: scaled(34))
                Spacer()
                PanelResizeHandle(corner: .topRight)
                    .frame(width: scaled(34), height: scaled(34))
            }
            Spacer()
            HStack {
                PanelResizeHandle(corner: .bottomLeft)
                    .frame(width: scaled(34), height: scaled(34))
                Spacer()
                PanelResizeHandle(corner: .bottomRight)
                    .frame(width: scaled(34), height: scaled(34))
            }
        }
        .frame(width: designSize - scaled(8), height: designSize - scaled(8))
        .allowsHitTesting(true)
    }

    private var enclosure: some View {
        let outerShape = RoundedRectangle(cornerRadius: scaled(62), style: .continuous)

        return ZStack {
            outerShape
                .fill(.ultraThinMaterial)
                .overlay {
                    outerShape
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.55), Color(red: 0.75, green: 0.80, blue: 0.88).opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay { outerShape.strokeBorder(.white.opacity(0.76), lineWidth: scaled(2)) }

            RoundedRectangle(cornerRadius: scaled(42), style: .continuous)
                .fill(.white.opacity(0.15))
                .overlay { RoundedRectangle(cornerRadius: scaled(42)).strokeBorder(.white.opacity(0.82), lineWidth: scaled(1.4)) }
                .padding(scaled(21))
                .shadow(color: .white.opacity(0.7), radius: scaled(10))
        }
        .clipShape(outerShape)
        .padding(scaled(6))
        .shadow(color: .black.opacity(0.20), radius: scaled(14), y: scaled(8))
    }

    private func commandKey(_ action: MicroAction, icon: String, title: String) -> some View {
        let isDecision = action == .approve || action == .decline
        let isHovered = hoveredCommand == action
        let hoverColor: Color = action == .approve ? .green : .red

        return Button { store.perform(action) } label: {
            KeyGlyph(
                systemName: icon,
                title: store.labelsVisible ? title : nil,
                activeGlow: action == .fast && store.isFastModeEnabled ? .yellow : nil
            )
        }
        .buttonStyle(
            MechanicalKeyStyle(
                bottomGlow: hoverColor,
                showsBottomGlow: isDecision && isHovered
            )
        )
        .frame(width: keySize, height: keySize)
        .onHover { isInside in
            guard isDecision else { return }
            if isInside {
                guard hoveredCommand != action else { return }
                hoveredCommand = action
                store.hoverDetent()
            } else if hoveredCommand == action {
                hoveredCommand = nil
            }
        }
        .accessibilityLabel(
            action == .fast
                ? (store.isFastModeEnabled ? "关闭 Fast 模式" : "启用 Fast 模式")
                : action.accessibilityLabel
        )
        .shortcutConfigurable(shortcutTarget(for: action), store: store)
    }

    private var toolboxSensor: some View {
        Button {
            isToolboxPresented.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.black, Color(red: 0.15, green: 0.16, blue: 0.18)], center: .center, startRadius: scaled(1), endRadius: scaled(27)))
                    .frame(width: scaled(44), height: scaled(44))
                    .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: scaled(2)) }
                    .shadow(color: .black.opacity(0.32), radius: scaled(4), y: scaled(3))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: scaled(18), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .help("打开 Codex 工具箱")
        .accessibilityLabel("打开 Codex 工具箱")
        .popover(isPresented: $isToolboxPresented, arrowEdge: .bottom) {
            ToolboxView { action in
                isToolboxPresented = false
                store.perform(action)
            }
        }
    }

    @ViewBuilder private var codexStatusGlyph: some View {
        if store.isCodexRunning {
            switch store.codexUsageMetric {
            case .weeklyRemaining:
                let remaining = store.weeklyQuota?.remainingPercent
                let color = quotaColor(for: remaining)
                ZStack {
                    quotaRing(progress: CGFloat(remaining ?? 0) / 100, color: color)
                    VStack(spacing: -scaled(1)) {
                        Text(remaining.map { "\($0)%" } ?? "--")
                            .font(.system(size: scaled(14), weight: .heavy, design: .rounded))
                        Text("周剩余")
                            .font(.system(size: scaled(7), weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black.opacity(0.78))
                }
            case .lifetimeConsumed:
                let lifetimeText = TokenCountFormatter.compact(store.lifetimeTokens)
                ZStack {
                    quotaRing(progress: store.lifetimeTokens == nil ? 0 : 1, color: .indigo)
                    VStack(spacing: -scaled(1)) {
                        Text(lifetimeText)
                            .font(.system(size: lifetimeTokenFontSize(for: lifetimeText), weight: .heavy, design: .rounded))
                        Text("累计消耗")
                            .font(.system(size: scaled(7), weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black.opacity(0.78))
                }
            }
        } else {
            CodexMarkView().scaleEffect(0.63)
        }
    }

    private func lifetimeTokenFontSize(for text: String) -> CGFloat {
        let numericText = text.trimmingCharacters(in: CharacterSet(charactersIn: "万亿"))
        return scaled(numericText.count > 4 ? 10 : 11)
    }

    private var codexStatusHelp: String {
        guard store.isCodexRunning else { return "打开 Codex" }
    switch store.codexUsageMetric {
    case .weeklyRemaining:
        guard let quota = store.weeklyQuota else {
            return "本周剩余 Token 读取中，点击查看累计 Token 消耗"
        }
            let resetText = quota.resetsAt.map {
                "，\($0.formatted(date: .abbreviated, time: .shortened)) 重置"
            } ?? ""
        return "本周剩余 \(quota.remainingPercent)% Token\(resetText)；点击查看累计 Token 消耗"
        case .lifetimeConsumed:
            return "累计消耗 \(TokenCountFormatter.full(store.lifetimeTokens)) Token；点击查看本周剩余额度"
        }
    }

    private func quotaRing(progress: CGFloat, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.32), lineWidth: scaled(5))
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: scaled(5), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: scaled(5))
        }
        .frame(width: scaled(48), height: scaled(48))
    }

    private func quotaColor(for remaining: Int?) -> Color {
        guard let remaining else { return .gray }
        if remaining <= 20 { return .red }
        if remaining <= 45 { return .orange }
        return .green
    }

    private var sideLabels: some View {
        Group {
            Text("Designed  by gumuup \(appVersion)")
                .rotationEffect(.degrees(-90))
                .offset(x: -scaled(201))
            Text("You can just build things")
                .rotationEffect(.degrees(90))
                .offset(x: scaled(201))
            Text("Let's build")
                .offset(y: scaled(202))
        }
        .font(.system(size: scaled(8.5), weight: .medium, design: .rounded))
        .foregroundStyle(.black.opacity(0.56))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.7.0"
    }

    private var screwHeads: some View {
        ForEach(Array(screwOffsets.enumerated()), id: \.offset) { _, offset in
            ZStack {
                Circle().fill(LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                Capsule().fill(.black.opacity(0.75)).frame(width: scaled(10), height: scaled(2)).rotationEffect(.degrees(45))
            }
            .frame(width: scaled(17), height: scaled(17))
            .shadow(color: .black.opacity(0.35), radius: scaled(2), y: scaled(2))
            .offset(offset)
        }
    }

    private var chromeControls: some View {
        HStack(spacing: scaled(6)) {
            Button {
                store.panelPosition = store.panelPosition == .top ? .bottom : .top
            } label: {
                Image(systemName: store.panelPosition == .top ? "pin.fill" : "pin.slash")
            }
            .foregroundStyle(store.panelPosition == .top ? Color.accentColor : .black.opacity(0.42))
            .help(store.panelPosition == .top ? "取消置顶，切换为沉底模式" : "钉住面板，切换为置顶模式")
            .accessibilityLabel(store.panelPosition == .top ? "取消置顶" : "置顶面板")

            Button(action: store.toggleLayer) {
                Image(systemName: store.labelsVisible ? "eye.fill" : "eye.slash.fill")
            }
            .foregroundStyle(store.labelsVisible ? Color.accentColor : .black.opacity(0.42))
            .help(store.labelsVisible ? "隐藏按键标注" : "显示按键标注")
            .accessibilityLabel(store.labelsVisible ? "隐藏按键标注" : "显示按键标注")
            .shortcutConfigurable(.toggleLabels, store: store)
            SettingsLink {
                Image(systemName: "gearshape.fill")
            }
            Button(action: closePanel) {
                Image(systemName: "xmark")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: scaled(10), weight: .bold))
        .foregroundStyle(.black.opacity(0.42))
        .padding(scaled(8))
        .background(.thinMaterial, in: Capsule())
        .offset(x: scaled(145), y: -scaled(188))
        .opacity(0.72)
    }

    @ViewBuilder private var feedbackToast: some View {
        if let recordingTarget = store.shortcutRecordingTarget {
            Button(action: store.cancelShortcutRecording) {
                HStack(spacing: scaled(5)) {
                    Text(store.feedbackMessage ?? "为 \(recordingTarget.title) 轻点任意单键，或按下组合键")
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: scaled(10), weight: .bold))
                }
                .font(.system(size: scaled(10), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, scaled(12))
                .padding(.vertical, scaled(7))
                .background(.indigo.opacity(0.9), in: Capsule())
                .shadow(radius: scaled(8))
            }
            .buttonStyle(.plain)
            .help("点击取消按键映射设置")
            .accessibilityLabel("取消 \(recordingTarget.title) 的按键映射设置")
            .offset(y: -scaled(201))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let message = store.feedbackMessage {
            Text(message)
                .font(.system(size: scaled(11), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, scaled(12))
                .padding(.vertical, scaled(7))
                .background(.black.opacity(0.78), in: Capsule())
                .shadow(radius: scaled(8))
                .offset(y: -scaled(201))
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.25), value: message)
        }
    }

    @ViewBuilder private var joystickShortcutMenu: some View {
        ForEach(joystickShortcutTargets, id: \.self) { target in
            Button {
                store.beginShortcutRecording(for: target)
            } label: {
                Label(joystickShortcutLabel(for: target), systemImage: "keyboard")
            }
        }

        if !configuredJoystickTargets.isEmpty {
            Divider()
            ForEach(configuredJoystickTargets, id: \.self) { target in
                Button(role: .destructive) {
                    store.clearShortcut(for: target)
                } label: {
                    Label("清除 \(target.title)", systemImage: "delete.left")
                }
            }
        }
    }

    private var joystickShortcutTargets: [ShortcutTarget] {
        [.joystickUp, .joystickRight, .joystickDown, .joystickLeft]
    }

    private var configuredJoystickTargets: [ShortcutTarget] {
        joystickShortcutTargets.filter { store.shortcut(for: $0) != nil }
    }

    private func joystickShortcutLabel(for target: ShortcutTarget) -> String {
        guard let shortcut = store.shortcut(for: target) else {
            return "设置 \(target.title)…"
        }
        let issue = store.shortcutRegistrationIssue(for: target)
        return "设置 \(target.title)…（\(shortcut.displayName) · \(shortcut.activationMode.label)"
            + (issue.map { " · ⚠︎ \($0)" } ?? "")
            + "）"
    }

    private func shortcutTarget(for action: MicroAction) -> ShortcutTarget {
        switch action {
        case .fast: .fast
        case .approve: .approve
        case .decline: .decline
        case .newTask: .newTask
        default: preconditionFailure("这个面板按键没有可配置的快捷键目标")
        }
    }

    private func reasoningShortcutTarget(for step: Int) -> ShortcutTarget {
        step < 0 ? .reasoningDown : .reasoningUp
    }

    private var screwOffsets: [CGSize] {
        [
            CGSize(width: -scaled(181), height: -scaled(181)), CGSize(width: scaled(181), height: -scaled(181)),
            CGSize(width: -scaled(181), height: scaled(181)), CGSize(width: scaled(181), height: scaled(181))
        ]
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * layoutScale
    }
}
