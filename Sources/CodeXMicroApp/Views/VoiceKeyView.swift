import SwiftUI

struct VoiceKeyView: View {
    let isActive: Bool
    let labelsVisible: Bool
    let onToggle: () -> Void
    @Environment(\.microLayoutScale) private var layoutScale

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: scaled(18), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isActive ? [Color(red: 0.83, green: 0.84, blue: 1), .white] : [.white, Color(red: 0.92, green: 0.94, blue: 0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay { RoundedRectangle(cornerRadius: scaled(18)).strokeBorder(.white.opacity(0.92), lineWidth: scaled(1.3)) }
                    .shadow(color: isActive ? .indigo.opacity(0.62) : .black.opacity(0.17), radius: scaled(isActive ? 2 : 7), y: scaled(isActive ? 1 : 5))
                VStack(spacing: scaled(4)) {
                    Image(systemName: isActive ? "waveform" : "mic")
                        .font(.system(size: scaled(24), weight: .medium))
                        .symbolEffect(.variableColor.iterative, isActive: isActive)
                    if labelsVisible {
                        Text(isActive ? "点击结束" : "点击说话")
                            .font(.system(size: scaled(8.5), weight: .semibold, design: .rounded))
                    }
                }
                .foregroundStyle(.black.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: scaled(18)))
        .accessibilityLabel(isActive ? "结束语音听写" : "开始语音听写")
        .help(isActive ? "点击结束 Codex 语音听写" : "点击开始 Codex 语音听写")
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
