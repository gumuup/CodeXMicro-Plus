import SwiftUI

struct MechanicalKeyStyle: ButtonStyle {
    var glow: Color = .clear
    var bottomGlow: Color = .clear
    var showsBottomGlow = false
    var cornerRadius: CGFloat = 17

    @Environment(\.microLayoutScale) private var layoutScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    if showsBottomGlow {
                        Ellipse()
                            .fill(bottomGlow.opacity(0.42))
                            .frame(width: scaled(58), height: scaled(14))
                            .blur(radius: scaled(10))
                            .offset(y: scaled(35))
                            .transition(.opacity.combined(with: .scale(scale: 0.82)))
                    }

                    RoundedRectangle(cornerRadius: scaled(cornerRadius), style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(configuration.isPressed ? 0.78 : 0.98),
                                    Color(red: 0.93, green: 0.95, blue: 0.98).opacity(0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            if showsBottomGlow {
                                RoundedRectangle(cornerRadius: scaled(cornerRadius), style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, bottomGlow.opacity(0.16)],
                                            startPoint: .center,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: scaled(cornerRadius), style: .continuous)
                                .strokeBorder(Color.white.opacity(0.92), lineWidth: scaled(1.3))
                        }
                        .shadow(color: glow.opacity(configuration.isPressed ? 0.2 : 0.55), radius: scaled(configuration.isPressed ? 4 : 12), y: scaled(2))
                        .shadow(color: Color.black.opacity(configuration.isPressed ? 0.09 : 0.18), radius: scaled(configuration.isPressed ? 2 : 5), y: scaled(configuration.isPressed ? 1 : 5))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .offset(y: scaled(configuration.isPressed ? 3 : 0))
            .animation(.spring(response: 0.13, dampingFraction: 0.72), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.18), value: showsBottomGlow)
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}

struct KeyGlyph: View {
    let systemName: String
    let title: String?
    var emphasized = false
    var activeGlow: Color? = nil

    @Environment(\.microLayoutScale) private var layoutScale

    private var isGlowing: Bool { activeGlow != nil }

    var body: some View {
        VStack(spacing: scaled(4)) {
            ZStack {
                if let activeGlow {
                    Ellipse()
                        .fill(activeGlow.opacity(0.88))
                        .frame(width: scaled(29), height: scaled(9))
                        .blur(radius: scaled(6))
                        .offset(y: scaled(8))
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }

                Image(systemName: systemName)
                    .font(.system(size: scaled(emphasized ? 25 : 22), weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .shadow(color: activeGlow?.opacity(0.95) ?? .clear, radius: scaled(7), y: scaled(6))
            }
            if let title {
                Text(title)
                    .font(.system(size: scaled(8.5), weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.16))
        .animation(.easeInOut(duration: 0.22), value: isGlowing)
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
