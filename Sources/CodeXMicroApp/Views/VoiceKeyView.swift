import SwiftUI

struct VoiceKeyView: View {
    let isActive: Bool
    let labelsVisible: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @GestureState private var pressing = false
    @Environment(\.microLayoutScale) private var layoutScale

    var body: some View {
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
                .shadow(color: isActive ? .indigo.opacity(0.62) : .black.opacity(0.17), radius: scaled(pressing ? 2 : 7), y: scaled(pressing ? 1 : 5))
            VStack(spacing: scaled(4)) {
                Image(systemName: isActive ? "waveform" : "mic")
                    .font(.system(size: scaled(24), weight: .medium))
                    .symbolEffect(.variableColor.iterative, isActive: isActive)
                if labelsVisible {
                    Text(isActive ? "松开结束" : "按住说话")
                        .font(.system(size: scaled(8.5), weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.black.opacity(0.8))
        }
        .scaleEffect(pressing ? 0.975 : 1)
        .offset(y: scaled(pressing ? 3 : 0))
        .animation(.spring(response: 0.13, dampingFraction: 0.72), value: pressing)
        .contentShape(RoundedRectangle(cornerRadius: scaled(18)))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in
                    if !state { onPress() }
                    state = true
                }
                .onEnded { _ in onRelease() }
        )
        .accessibilityLabel("按住说话")
        .help("按住开始 Codex 语音听写，松开结束")
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
