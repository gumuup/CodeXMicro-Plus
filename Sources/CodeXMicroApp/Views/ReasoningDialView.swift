import SwiftUI

struct ReasoningDialView: View {
    let level: ReasoningLevel
    let onAdjust: (Int) -> Void
    @Environment(\.microLayoutScale) private var layoutScale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: scaled(17), style: .continuous)
                .fill(Color.white.opacity(0.36))
                .overlay {
                    RoundedRectangle(cornerRadius: scaled(17), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: scaled(1))
                }
                .shadow(color: .black.opacity(0.14), radius: scaled(5), y: scaled(4))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.25, green: 0.26, blue: 0.28), .black],
                        center: .topLeading,
                        startRadius: scaled(1),
                        endRadius: scaled(27)
                    )
                )
                .frame(width: scaled(51), height: scaled(51))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.22), lineWidth: scaled(1))
                    Capsule().fill(.white.opacity(0.78)).frame(width: scaled(3), height: scaled(15)).offset(y: -scaled(14))
                }
                .rotationEffect(.degrees(level.dialAngleDegrees))
                .animation(.snappy(duration: 0.16), value: level)
                .shadow(color: .black.opacity(0.35), radius: scaled(4), y: scaled(4))

            Text(level.label)
                .font(.system(size: scaled(8), weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .offset(y: scaled(8))

            DialInteractionView { step in
                onAdjust(step)
            }
            .background(Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: scaled(17)))
        .help("点击左侧减小、右侧增加；也可双指滚动或上下拖动")
        .accessibilityLabel("推理强度旋钮，当前\(level.label)")
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
