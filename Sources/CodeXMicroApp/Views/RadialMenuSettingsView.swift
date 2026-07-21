import AppKit
import SwiftUI

struct RadialMenuSettingsView: View {
    @ObservedObject var store: CodexStore
    @State private var selection: UUID?

    private let target = ShortcutTarget.radialMenu

    var body: some View {
        VStack(spacing: 0) {
            hotKeyHeader
            Divider()

            HSplitView {
                profileSidebar
                    .frame(minWidth: 150, idealWidth: 164, maxWidth: 185)

                wheelAndItems
                    .frame(minWidth: 270, idealWidth: 292)

                editor
                    .frame(minWidth: 330, idealWidth: 360)
            }
        }
        .onAppear {
            if selection == nil { selection = store.radialMenuItems.first?.id }
        }
        .onChange(of: store.radialMenuItems) { _, items in
            if !items.contains(where: { $0.id == selection }) {
                selection = items.first?.id
            }
        }
        .onChange(of: store.selectedRadialMenuProfileID) { _, _ in
            selection = store.radialMenuItems.first?.id
        }
    }

    private var hotKeyHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("快速启动轮盘")
                    .font(.headline)
                Text("按住快捷键，移向操作后松手执行；轻按会保持显示，可直接点击。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        store.restoreDefaultRadialMenu()
                    } label: {
                        Label("恢复预设", systemImage: "arrow.counterclockwise.circle")
                    }
                    .controlSize(.large)
                    .help("恢复 \(store.selectedRadialMenuProfile?.name ?? "当前应用") 的轮盘预设")

                    Button {
                        store.previewRadialMenu()
                    } label: {
                        Label("预览", systemImage: "eye")
                    }
                    .controlSize(.large)

                    Button {
                        if store.shortcutRecordingTarget == target {
                            store.cancelShortcutRecording()
                        } else {
                            store.beginShortcutRecording(for: target)
                        }
                    } label: {
                        Text(store.shortcutRecordingTarget == target ? "请按键…" : binding?.displayName ?? "设置…")
                            .frame(minWidth: 82)
                    }
                    .controlSize(.large)

                    Button {
                        store.restoreDefaultShortcut(for: target)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(binding == ShortcutDefaults.bindings[target])
                    .help("恢复默认快捷键 ⌃Z")
                }

                Label(statusText, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(18)
    }

    private var profileSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "globe")
                    .foregroundStyle(store.radialMenuGlobalModeEnabled ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("全局模式")
                        .font(.system(size: 12, weight: .semibold))
                    Text(store.radialMenuGlobalModeEnabled ? "所有应用统一使用" : "按应用自动匹配")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { store.radialMenuGlobalModeEnabled },
                    set: { store.setRadialMenuGlobalModeEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Divider()

            Text("应用预设")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 12)

            List(selection: profileSelection) {
                ForEach(store.radialMenuProfiles) { profile in
                    HStack(spacing: 8) {
                        applicationIcon(for: profile)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            if profile.isGlobal || profile.isDefault {
                                Text(profile.isGlobal ? "所有应用" : "默认")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        if !profile.isDefault && !profile.isGlobal {
                            Button("移除应用预设", role: .destructive) {
                                store.removeRadialMenuProfile(id: profile.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 6) {
                Button {
                    addApplicationProfile()
                } label: {
                    Label("添加应用", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 0)

                if let profile = store.selectedRadialMenuProfile,
                   !profile.isDefault, !profile.isGlobal {
                    Button(role: .destructive) {
                        store.removeRadialMenuProfile(id: profile.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("移除 \(profile.name) 预设")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private var wheelAndItems: some View {
        VStack(alignment: .leading, spacing: 12) {
            MiniRadialMenuPreview(items: store.radialMenuItems, selection: $selection)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack {
                Text("轮盘操作")
                    .font(.headline)
                Text("\(store.radialMenuItems.count)/12")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.addRadialMenuItem()
                    selection = store.radialMenuItems.last?.id
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .disabled(store.radialMenuItems.count >= 12)
            }

            List {
                ForEach(store.radialMenuItems) { item in
                    RadialMenuOperationRow(
                        item: item,
                        isSelected: selection == item.id,
                        canDelete: store.radialMenuItems.count > 1,
                        onSelect: {
                            selection = item.id
                        },
                        onDelete: {
                            store.removeRadialMenuItem(id: item.id)
                        },
                        onDrop: { draggedID, insertAfter in
                            store.moveRadialMenuItem(
                                id: draggedID,
                                relativeTo: item.id,
                                insertAfter: insertAfter
                            )
                            selection = draggedID
                        }
                    )
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.inset)

        }
        .padding(14)
    }

    @ViewBuilder
    private var editor: some View {
        if let item = store.radialMenuItems.first(where: { $0.id == selection }) {
            RadialMenuItemEditor(
                item: item,
                shortcutRegistrationFailed: !store.isRadialItemShortcutActive(itemID: item.id),
                onShortcutRecordingChanged: store.setRadialItemShortcutRecording,
                canMoveUp: store.radialMenuItems.first?.id != item.id,
                canMoveDown: store.radialMenuItems.last?.id != item.id,
                onChange: store.updateRadialMenuItem,
                onMove: { store.moveRadialMenuItem(id: item.id, offset: $0) },
                onDelete: { store.removeRadialMenuItem(id: item.id) }
            )
            .id(item.id)
        } else {
            ContentUnavailableView("选择一个轮盘操作", systemImage: "circle.hexagongrid")
        }
    }

    private var binding: KeyboardShortcutBinding? { store.shortcut(for: target) }

    private var profileSelection: Binding<UUID?> {
        Binding(
            get: { store.selectedRadialMenuProfileID },
            set: { id in
                guard let id else { return }
                store.selectRadialMenuProfile(id: id)
            }
        )
    }

    @ViewBuilder
    private func applicationIcon(for profile: RadialMenuProfile) -> some View {
        if profile.isGlobal {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(store.radialMenuGlobalModeEnabled ? .blue : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        } else if FileManager.default.fileExists(atPath: profile.applicationPath) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: profile.applicationPath))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: profile.isDefault ? "sparkles" : "app.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(profile.isDefault ? .green : .blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func addApplicationProfile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择需要专属轮盘预设的应用"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let id = store.addRadialMenuProfile(applicationURL: url) {
            store.selectRadialMenuProfile(id: id)
            selection = store.radialMenuItems.first?.id
        }
    }

    private var statusText: String {
        if let issue = store.shortcutRegistrationIssue(for: target) { return issue }
        guard let binding else { return "轮盘热键未设置" }
        return store.isShortcutActive(target) ? "\(binding.displayName) 轮盘热键正常" : "\(binding.displayName) 轮盘热键未启动"
    }

    private var statusIcon: String {
        store.isShortcutActive(target) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        store.isShortcutActive(target) ? .green : .orange
    }
}

private struct RadialMenuOperationRow: View {
    let item: RadialMenuItem
    let isSelected: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDrop: (UUID, Bool) -> Void

    @State private var isHovering = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 8) {
            SixDotDragHandle()
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .opacity(showsControls ? 1 : 0)
                .allowsHitTesting(showsControls)
                .draggable(item.id.uuidString) {
                    Label(item.title, systemImage: item.systemImage)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .help("拖动调整位置")

            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 25, height: 25)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text(item.action.kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(item.triggerShortcut?.displayName ?? item.action.summary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: 72, alignment: .trailing)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 16, height: 24)
            }
            .buttonStyle(.borderless)
            .opacity(showsControls ? 1 : 0)
            .disabled(!canDelete)
            .allowsHitTesting(showsControls && canDelete)
            .help(canDelete ? "删除 \(item.title)" : "轮盘至少保留一个操作")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackground)
        }
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .dropDestination(for: String.self) { draggedValues, location in
            guard let value = draggedValues.first,
                  let draggedID = UUID(uuidString: value),
                  draggedID != item.id else { return false }
            onDrop(draggedID, location.y > 18)
            return true
        } isTargeted: {
            isDropTarget = $0
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var rowBackground: Color {
        if isDropTarget { return Color.accentColor.opacity(0.14) }
        if isSelected { return Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }
        return .clear
    }

    private var showsControls: Bool {
        isHovering || isSelected
    }
}

private struct SixDotDragHandle: View {
    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2.5) {
                    Circle().frame(width: 3.5, height: 3.5)
                    Circle().frame(width: 3.5, height: 3.5)
                }
            }
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .frame(width: 17, height: 25)
        .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.75)
        }
    }
}

private struct MiniRadialMenuPreview: View {
    let items: [RadialMenuItem]
    @Binding var selection: UUID?

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = Angle.degrees(-90 + Double(index) * 360 / Double(max(items.count, 1)))
                Button {
                    selection = item.id
                } label: {
                    RadialActionIcon(item: item, size: 38, selected: selection == item.id)
                        .scaleEffect(selection == item.id ? 1.16 : 1)
                        .shadow(
                            color: selection == item.id ? Color.accentColor.opacity(0.3) : .black.opacity(0.13),
                            radius: selection == item.id ? 8 : 3,
                            y: 2
                        )
                }
                .buttonStyle(.plain)
                .offset(x: cos(angle.radians) * 82, y: sin(angle.radians) * 82)
                .animation(.spring(response: 0.22, dampingFraction: 0.68), value: selection)
            }

            HStack(spacing: 6) {
                Image(systemName: selection == nil ? "cursorarrow.motionlines" : "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(items.first(where: { $0.id == selection })?.title ?? "选择操作")
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 76, minHeight: 27)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .frame(height: 220)
    }
}

private struct RadialMenuItemEditor: View {
    @State private var draft: RadialMenuItem
    @State private var showsIconPicker = false
    @State private var shortcutNames: [String] = []

    let item: RadialMenuItem
    let shortcutRegistrationFailed: Bool
    let onShortcutRecordingChanged: (Bool) -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onChange: (RadialMenuItem) -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    init(
        item: RadialMenuItem,
        shortcutRegistrationFailed: Bool,
        onShortcutRecordingChanged: @escaping (Bool) -> Void,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onChange: @escaping (RadialMenuItem) -> Void,
        onMove: @escaping (Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: item)
        self.item = item
        self.shortcutRegistrationFailed = shortcutRegistrationFailed
        self.onShortcutRecordingChanged = onShortcutRecordingChanged
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onChange = onChange
        self.onMove = onMove
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            Section("显示") {
                HStack {
                    Button {
                        showsIconPicker.toggle()
                    } label: {
                        Image(systemName: draft.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 44, height: 38)
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showsIconPicker, arrowEdge: .bottom) {
                        RadialIconPicker(selection: $draft.systemImage)
                    }

                    TextField("操作名称", text: $draft.title)
                }
            }

            Section("操作") {
                Picker("类型", selection: kindBinding) {
                    ForEach(RadialMenuActionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }

                actionConfiguration

                HStack {
                    Label("快捷键", systemImage: "command")
                    Spacer()
                    if shortcutRegistrationFailed, draft.triggerShortcut != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("该组合键被其他应用或系统快捷键占用")
                    }
                    OptionalShortcutRecorderButton(
                        binding: $draft.triggerShortcut,
                        onRecordingChanged: onShortcutRecordingChanged
                    )
                }
            }

            Section {
                HStack {
                    Button { onMove(-1) } label: { Label("上移", systemImage: "arrow.up") }
                        .disabled(!canMoveUp)
                    Button { onMove(1) } label: { Label("下移", systemImage: "arrow.down") }
                        .disabled(!canMoveDown)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Label("删除", systemImage: "trash")
                    }
                }
            }

            Section("说明") {
                Text("操作按列表顺序顺时针排列。建议保留 6–10 项，以便形成稳定的方向记忆。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, value in onChange(value) }
        .onChange(of: item) { _, value in
            if draft != value { draft = value }
        }
        .task { shortcutNames = installedShortcutNames() }
    }

    @ViewBuilder
    private var actionConfiguration: some View {
        switch draft.action {
        case .unconfigured:
            Label("请选择操作类型后完成配置", systemImage: "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

        case let .codexToolbox(action):
            Picker("功能", selection: Binding(
                get: { action },
                set: { newValue in
                    draft.action = .codexToolbox(newValue)
                    draft.title = newValue.title
                    draft.systemImage = newValue.systemImage
                }
            )) {
                ForEach(ToolboxAction.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }

        case let .keyboardShortcut(binding):
            HStack {
                Text("组合键")
                Spacer()
                LocalShortcutRecorderButton(binding: Binding(
                    get: { binding },
                    set: { draft.action = .keyboardShortcut($0) }
                ))
            }

        case let .application(path):
            fileSelectionRow(title: path.isEmpty ? "请选择应用程序" : URL(fileURLWithPath: path).lastPathComponent) {
                guard let url = chooseApplication() else { return }
                draft.action = .application(path: url.path)
                draft.title = url.deletingPathExtension().lastPathComponent
                draft.systemImage = "app.fill"
            }

        case let .systemApplication(path):
            Picker("系统应用", selection: Binding(
                get: { path },
                set: { selectedPath in
                    guard let application = SystemApplicationCatalog.applications.first(where: {
                        $0.path == selectedPath
                    }) else { return }
                    draft.action = .systemApplication(path: application.path)
                    draft.title = application.name
                    draft.systemImage = "macwindow"
                }
            )) {
                Text("请选择系统应用").tag("")
                ForEach(SystemApplicationCatalog.applications) { application in
                    Text(application.name).tag(application.path)
                }
            }

        case let .plugin(identifier):
            Picker("插件", selection: Binding(
                get: { RadialPluginPreset(rawValue: identifier) ?? .plugins },
                set: { plugin in
                    draft.action = .plugin(identifier: plugin.rawValue)
                    draft.title = plugin.title
                    draft.systemImage = plugin.systemImage
                }
            )) {
                ForEach(RadialPluginPreset.allCases) { plugin in
                    Label(plugin.title, systemImage: plugin.systemImage).tag(plugin)
                }
            }

        case let .website(url):
            TextField("https://example.com", text: Binding(
                get: { url },
                set: { draft.action = .website(url: $0) }
            ))

        case let .pasteText(text):
            TextEditor(text: Binding(
                get: { text },
                set: { draft.action = .pasteText($0) }
            ))
            .font(.body)
            .frame(minHeight: 90)

        case let .folder(path):
            fileSelectionRow(title: path.isEmpty ? "请选择文件夹" : path) {
                guard let url = chooseFolder() else { return }
                draft.action = .folder(path: url.path)
                draft.title = url.lastPathComponent
                draft.systemImage = "folder.fill"
            }

        case let .shortcut(name):
            TextField("快捷指令名称", text: Binding(
                get: { name },
                set: { draft.action = .shortcut(name: $0) }
            ))
            if !shortcutNames.isEmpty {
                Picker("本机快捷指令", selection: Binding(
                    get: { shortcutNames.contains(name) ? name : "" },
                    set: { value in
                        guard !value.isEmpty else { return }
                        draft.action = .shortcut(name: value)
                        draft.title = value
                    }
                )) {
                    Text("手动填写").tag("")
                    ForEach(shortcutNames, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    private var kindBinding: Binding<RadialMenuActionKind> {
        Binding(
            get: { draft.action.kind },
            set: { kind in
                draft.action = .defaultAction(for: kind)
                draft.title = kind.title
                draft.systemImage = kind.systemImage
            }
        )
    }

    private func fileSelectionRow(title: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(title).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            Button("选择…", action: choose)
        }
    }

    private func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func installedShortcutNames() -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

private struct RadialIconPicker: View {
    @Binding var selection: String
    @State private var query = ""
    @State private var showsCodexOnly = true

    private let columns = Array(repeating: GridItem(.fixed(38), spacing: 7), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("图标来源", selection: $showsCodexOnly) {
                Text("Codex").tag(true)
                Text("macOS 系统符号").tag(false)
            }
            .pickerStyle(.segmented)

            TextField("搜索 SF Symbol 名称", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            selection = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 34)
                                .background(selection == symbol ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(selection == symbol ? Color.accentColor : Color.primary.opacity(0.08))
                                }
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 390, height: 390)
    }

    private var filteredSymbols: [String] {
        let source = showsCodexOnly ? RadialIconCatalog.codexSymbols : RadialIconCatalog.allSymbols
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? source : source.filter { $0.lowercased().contains(normalized) }
    }
}

@MainActor
private final class LocalShortcutRecorder: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?
    private var onStop: (() -> Void)?

    func start(
        onStop: (() -> Void)? = nil,
        onCapture: @escaping (KeyboardShortcutBinding) -> Void
    ) {
        stop()
        self.onStop = onStop
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stop()
                return nil
            }
            var modifiers: ShortcutModifiers = []
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            let binding = KeyboardShortcutBinding(
                keyCode: event.keyCode,
                modifiers: modifiers,
                keyLabel: ShortcutKeyCatalog.label(for: event.keyCode) ?? "Key \(event.keyCode)"
            )
            self.stop()
            onCapture(binding)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        let callback = onStop
        onStop = nil
        callback?()
    }
}

private struct LocalShortcutRecorderButton: View {
    @Binding var binding: KeyboardShortcutBinding
    @StateObject private var recorder = LocalShortcutRecorder()

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start { binding = $0 }
            }
        } label: {
            Text(recorder.isRecording ? "请按组合键…" : binding.displayName)
                .frame(minWidth: 100)
        }
        .onDisappear { recorder.stop() }
    }
}

private struct OptionalShortcutRecorderButton: View {
    @Binding var binding: KeyboardShortcutBinding?
    let onRecordingChanged: (Bool) -> Void
    @StateObject private var recorder = LocalShortcutRecorder()
    @State private var validationMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    validationMessage = nil
                    onRecordingChanged(true)
                    recorder.start(onStop: { onRecordingChanged(false) }) { captured in
                        guard !captured.modifiers.isEmpty else {
                            validationMessage = "请至少按住一个修饰键"
                            return
                        }
                        binding = captured
                    }
                }
            } label: {
                Text(recorder.isRecording ? "请按组合键…" : binding?.displayName ?? "未设置")
                    .frame(minWidth: 94)
            }

            if binding != nil {
                Button {
                    recorder.stop()
                    validationMessage = nil
                    binding = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("清除快捷键")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .offset(y: 13)
            }
        }
        .onDisappear {
            recorder.stop()
            onRecordingChanged(false)
        }
    }
}
