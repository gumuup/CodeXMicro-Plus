import SwiftUI

struct AgentKeyView: View {
    let index: Int
    let task: CodexTask?
    let labelsVisible: Bool
    let action: () -> Void

    @Environment(\.microLayoutScale) private var layoutScale

    private var status: CodexTaskStatus { task?.status ?? .idle }

    var body: some View {
        Button(action: action) {
            VStack(spacing: scaled(7)) {
                HStack(spacing: 0) {
                    Text("A\(index + 1)")
                        .font(.system(size: scaled(9), weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.62))
                    Spacer(minLength: scaled(3))
                    ZStack {
                        Circle()
                            .fill(status.color.opacity(task == nil ? 0.12 : 0.3))
                            .frame(width: scaled(21), height: scaled(21))
                            .blur(radius: scaled(5))
                        Circle()
                            .fill(status.color)
                            .frame(width: scaled(task == nil ? 7 : 10), height: scaled(task == nil ? 7 : 10))
                            .shadow(color: status.color, radius: scaled(task?.status == .active ? 8 : 5))
                    }
                }
                .frame(width: scaled(49))
                if labelsVisible {
                    Text(task?.shortTitle ?? "空闲")
                        .font(.system(size: scaled(7.3), weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.67))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: scaled(59))
                }
            }
        }
        .buttonStyle(MechanicalKeyStyle(glow: status.color))
        .help(task.map { "\($0.status.label)：\($0.shortTitle)" } ?? "暂无任务")
        .accessibilityLabel(task.map { "Agent \(index + 1)，\($0.status.label)，\($0.shortTitle)" } ?? "Agent \(index + 1)，空闲")
        .disabled(task == nil)
        .opacity(task == nil ? 0.78 : 1)
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * layoutScale }
}
