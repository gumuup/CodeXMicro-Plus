import SwiftUI

struct JoystickView: View {
    let onTrigger: (JoystickDirection) -> Void
    let onDetent: () -> Void
    @GestureState private var liveOffset: CGSize = .zero
    @State private var activeDirection: JoystickDirection?
    @Environment(\.microLayoutScale) private var layoutScale

    private var constrainedOffset: CGSize {
        let length = max(hypot(liveOffset.width, liveOffset.height), 1)
        let scale = min(scaled(18) / length, 1)
        return CGSize(width: liveOffset.width * scale, height: liveOffset.height * scale)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: scaled(17), style: .continuous)
                .fill(Color.white.opacity(0.46))
                .overlay {
                    RoundedRectangle(cornerRadius: scaled(17), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: scaled(1))
                }
                .shadow(color: .black.opacity(0.12), radius: scaled(5), y: scaled(4))

            ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                Image(systemName: marker.symbol)
                    .font(.system(size: scaled(7), weight: .bold))
                    .foregroundStyle(.black.opacity(0.38))
                    .offset(marker.offset)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(red: 0.77, green: 0.79, blue: 0.83)],
                        center: .topLeading,
                        startRadius: scaled(1),
                        endRadius: scaled(30)
                    )
                )
                .frame(width: scaled(43), height: scaled(43))
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.78)).frame(width: scaled(12), height: scaled(8)).blur(radius: scaled(3)).offset(x: scaled(8), y: scaled(7))
                }
                .shadow(color: .black.opacity(0.28), radius: scaled(5), y: scaled(5))
                .offset(constrainedOffset)
        }
        .contentShape(RoundedRectangle(cornerRadius: scaled(17)))
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($liveOffset) { value, state, _ in state = value.translation }
                .onChanged { value in
                    let direction = direction(for: value.translation)
                    guard direction != activeDirection else { return }
                    activeDirection = direction
                    if direction != nil {
                        onDetent()
                    }
                }
                .onEnded { value in
                    activeDirection = nil
                    guard let direction = direction(for: value.translation) else { return }
                    onTrigger(direction)
                }
        )
        .help("摇动：左上一个任务、右下一个任务、上计划模式、下目标模式")
        .accessibilityLabel("任务导航摇杆")
    }

    private var markers: [(symbol: String, offset: CGSize)] {
        [
            ("chevron.up", CGSize(width: 0, height: -scaled(28))),
            ("chevron.right", CGSize(width: scaled(28), height: 0)),
            ("chevron.down", CGSize(width: 0, height: scaled(28))),
            ("chevron.left", CGSize(width: -scaled(28), height: 0))
        ]
    }

    private func direction(for translation: CGSize) -> JoystickDirection? {
        guard hypot(translation.width, translation.height) > scaled(12) else { return nil }
        if abs(translation.width) > abs(translation.height) {
            return translation.width > 0 ? .right : .left
        }
        return translation.height > 0 ? .down : .up
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
