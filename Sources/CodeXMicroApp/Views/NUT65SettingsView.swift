import AppKit
import SwiftUI

struct NUT65SettingsView: View {
    @ObservedObject var keyboard: NUT65Store
    @AppStorage("nut65.editor.layer") private var layer = 2
    @State private var testResult = "尚未实按验证"
    @State private var selected: NUT65Key?
    @State private var target: UInt16 = 41
    @State private var modifiers: UInt16 = 0
    @State private var search = ""

    private var currentCode: UInt16? {
        guard let selected, let snapshot = keyboard.snapshot, snapshot.layers.indices.contains(layer) else { return nil }
        return snapshot.layers[layer][selected.id]
    }
    private var desiredCode: UInt16 { target | (target >= 4 && target <= 115 ? modifiers : 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("NUT65", systemImage: "keyboard").font(.title2.bold())
                        Text("板载按键映射 · USB 有线配置").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("读取键盘") { keyboard.read() }.disabled(keyboard.busy)
                }
                if let url = Bundle.main.url(forResource: "nut65-keyboard", withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 90)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("NUT65 键盘产品图")
                }
                HStack(spacing: 8) {
                    if keyboard.busy { ProgressView().controlSize(.small) }
                    Text(keyboard.status).font(.callout)
                        .foregroundStyle(keyboard.failed ? Color.orange : Color.secondary)
                        .textSelection(.enabled)
                }
                if let snapshot = keyboard.snapshot {
                    Picker("编辑层", selection: $layer) {
                        ForEach(snapshot.layers.indices, id: \.self) { index in Text(NUT65Layers.title(index, count: snapshot.layers.count)).tag(index) }
                    }.pickerStyle(.segmented).disabled(keyboard.busy)
                    Text("编辑层不会切换键盘当前模式。通常 Win 用层 0／1，Mac 用层 2／3；请与键盘自身模式一致。当前生效层尚未自动检测。").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(testResult).font(.caption.monospaced()).foregroundStyle(.secondary)
                        NUT65KeyTestView { keyCode, characters in
                            let label = characters.isEmpty ? "特殊键" : characters.uppercased()
                            testResult = "系统实际收到：\(label) · macOS 键码 \(keyCode)"
                        }.frame(height: 38)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                    keyboardLayout(snapshot)
                    if let selected, let current = currentCode {
                        editor(selected, current: current)
                    } else {
                        Label("点击键盘上的按键开始修改", systemImage: "hand.point.up.left")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                    }
                } else {
                    Image(systemName: "keyboard").font(.system(size: 90, weight: .ultraLight))
                        .foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                Divider()
                Text("写入保存在键盘中；关闭本应用后仍由键盘执行。每次只修改选中的一个键，写入前自动备份全部映射。蓝牙／2.4G 下的配置和生效情况尚未验证。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("撤销上次改键") { keyboard.undoLastChange() }
                        .disabled(keyboard.undo == nil || keyboard.busy)
                    Button("打开备份文件夹") {
                        try? FileManager.default.createDirectory(at: NUT65Store.backupDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(NUT65Store.backupDirectory)
                    }
                    Spacer()
                    Link("厂家网页驱动", destination: URL(string: "https://weikavnut65.hsgaming.cn/")!)
                }.font(.caption)
            }.padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        .onAppear {
            if let snapshot = keyboard.snapshot { layer = NUT65Layers.initialLayer(saved: layer, count: snapshot.layers.count) }
            else { keyboard.read() }
        }
        .onChange(of: layer) { _, _ in loadSelection() }
        .onChange(of: keyboard.busy) { _, busy in
            if !busy {
                if let snapshot = keyboard.snapshot { layer = NUT65Layers.initialLayer(saved: layer, count: snapshot.layers.count) }
                loadSelection()
            }
        }
    }

    private func keyboardLayout(_ snapshot: NUT65Snapshot) -> some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 17.3
            ZStack(alignment: .topLeading) {
                ForEach(NUT65Layout.keys) { key in
                    let code = snapshot.layers.indices.contains(layer) ? snapshot.layers[layer][key.id] : 0
                    Button { selected = key; loadSelection() } label: {
                        VStack(spacing: 3) {
                            Text(key.label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            Text(NUT65Keycodes.title(code)).font(.system(size: 10, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(width: max(15, key.width * unit - 3), height: 42)
                        .background(selected?.id == key.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected?.id == key.id ? Color.accentColor : Color.primary.opacity(0.1)))
                    }.buttonStyle(.plain)
                        .help("\(key.label)：\(NUT65Keycodes.title(code)) · 行 \(key.row)，列 \(key.column)")
                        .offset(x: key.x * unit, y: key.y * 45)
                }
            }.disabled(keyboard.busy)
        }.frame(height: 240)
    }

    private func editor(_ key: NUT65Key, current: UInt16) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(key.label) → \(NUT65Keycodes.title(desiredCode))").font(.headline)
                Spacer()
                Text("此层已保存：\(NUT65Keycodes.title(current))").font(.caption).foregroundStyle(.secondary)
            }
            TextField("搜索目标键，例如 Command、F12、音量", text: $search).textFieldStyle(.roundedBorder)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(NUT65Keycodes.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in
                        Button(item.title) { target = item.code }
                            .buttonStyle(.bordered).tint(target == item.code ? .accentColor : .secondary)
                    }
                    if search.isEmpty, let snapshot = keyboard.snapshot {
                        ForEach(snapshot.layers.indices, id: \.self) { index in
                            Button("Fn → 层 \(index)") { target = UInt16(0x5220 + index) }
                                .buttonStyle(.bordered).tint(target == UInt16(0x5220 + index) ? .accentColor : .secondary)
                        }
                    }
                }.padding(.vertical, 3)
            }
            HStack {
                ForEach([UInt16(0x0100), 0x0200, 0x0400, 0x0800], id: \.self) { mask in
                    Toggle(modifierTitle(mask), isOn: Binding(get: { modifiers & mask != 0 }, set: { on in
                        if on { modifiers |= mask } else { modifiers &= ~mask }
                    })).toggleStyle(.checkbox).disabled(!(4...115).contains(target))
                }
            }.font(.caption)
            HStack {
                Text("层 \(layer) · \(key.label) → \(NUT65Keycodes.title(desiredCode))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("写入层 \(layer)") { testResult = "尚未实按验证"; keyboard.save(code: desiredCode, layer: layer, key: key) }
                    .buttonStyle(.borderedProminent).disabled(current == desiredCode)
            }
        }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .disabled(keyboard.busy)
    }
    private func modifierTitle(_ mask: UInt16) -> String {
        switch mask { case 0x0100: "⌃ Control"; case 0x0200: "⇧ Shift"; case 0x0400: "⌥ Option"; default: "⌘ Command" }
    }
    private func loadSelection() {
        search = ""; modifiers = 0
        guard let code = currentCode else { return }
        if (0x0100...0x0fff).contains(code), (4...115).contains(code & 255) {
            target = code & 255; modifiers = code & 0x0f00
        } else { target = code }
    }
}
