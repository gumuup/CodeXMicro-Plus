import SwiftUI

struct AudioDiagnosticsView: View {
    @ObservedObject var audio: AudioSettingsStore
    @StateObject private var test = AudioDiagnostics()
    @State private var inputUID = ""
    @State private var outputUID = ""
    private var input: SystemAudioDevice? { audio.inputs.first { $0.uid == inputUID } }
    private var output: SystemAudioDevice? { audio.outputDevices.first { $0.uid == outputUID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("声音测试").font(.caption.bold())
                Picker("输入", selection: $inputUID) {
                    Text("选择输入").tag("")
                    ForEach(audio.inputs) { Text($0.name).tag($0.uid) }
                }.labelsHidden().accessibilityLabel("测试输入设备")
                Button("测试输入 · 5 秒") { if let input { test.testInput(input) } }.disabled(test.running || input == nil)
                ProgressView(value: Double(min(1, test.level * 10))).frame(width: 55).accessibilityLabel("测试输入电平")
                Picker("输出", selection: $outputUID) {
                    Text("选择输出").tag("")
                    ForEach(audio.outputDevices) { Text($0.name).tag($0.uid) }
                }.labelsHidden().accessibilityLabel("测试输出设备")
                Button("播放测试音") { if let output { test.testOutput(output) } }.disabled(test.running || output == nil)
                if test.running { Button("停止") { test.stop() } }
            }.controlSize(.small)
            Text(test.result).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Text("仅测试所选设备，不更改系统输入／输出。混音送入输入法需选择虚拟输出，并在输入法选择同名麦克风。").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10).background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            inputUID = audio.inputs.first { $0.id == audio.defaultInput }?.uid ?? ""
            outputUID = audio.outputDevices.first { $0.id == audio.defaultOutput }?.uid ?? ""
        }
        .onChange(of: inputUID) { _, _ in test.stop() }
        .onChange(of: outputUID) { _, _ in test.stop() }
        .onChange(of: audio.devices) { _, _ in test.stop() }
        .onDisappear { test.stop() }
    }
}
