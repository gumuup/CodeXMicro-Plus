import AppKit
import SwiftUI

@MainActor
final class RadialMenuInteractionState: ObservableObject {
    @Published var selectedItemID: UUID?
    @Published var isPresented = false
    @Published var items: [RadialMenuItem] = []
}

struct RadialMenuView: View {
    @ObservedObject var store: CodexStore
    @ObservedObject var interaction: RadialMenuInteractionState
    let onSelect: (RadialMenuItem) -> Void
    let onDismiss: () -> Void

    private let canvasSize: CGFloat = 430
    private let ringRadius: CGFloat = 137
    private let deadZoneRadius: CGFloat = 52

    var body: some View {
        ZStack {
            Color.clear

            ForEach(Array(interaction.items.enumerated()), id: \.element.id) { index, item in
                wheelButton(item, index: index, count: interaction.items.count)
            }

            centerLabel
        }
        .frame(width: canvasSize, height: canvasSize)
        .contentShape(Rectangle())
        .onContinuousHover(perform: updateDirectionalSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速启动轮盘")
    }

    private func wheelButton(_ item: RadialMenuItem, index: Int, count: Int) -> some View {
        let angle = Angle.degrees(-90 + Double(index) * 360 / Double(max(count, 1)))
        let selected = interaction.selectedItemID == item.id
        let visibleRadius = interaction.isPresented ? ringRadius : ringRadius * 0.2

        return Button {
            onSelect(item)
        } label: {
            RadialActionIcon(item: item, size: 48, selected: selected)
                .scaleEffect(selected ? 1.18 : 1)
                .offset(y: selected ? -2 : 0)
                .shadow(
                    color: selected ? Color.accentColor.opacity(0.34) : .black.opacity(0.18),
                    radius: selected ? 14 : 6,
                    y: selected ? 5 : 3
                )
        }
        .buttonStyle(.plain)
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .offset(x: cos(angle.radians) * visibleRadius, y: sin(angle.radians) * visibleRadius)
        .opacity(interaction.isPresented ? 1 : 0)
        .scaleEffect(interaction.isPresented ? 1 : 0.72)
        .animation(
            .spring(response: 0.34, dampingFraction: 0.72)
                .delay(Double(index) * 0.014),
            value: interaction.isPresented
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.66), value: selected)
        .help("\(item.title) · \(item.action.kind.title)")
        .accessibilityLabel(item.title)
        .accessibilityHint("\(item.action.kind.title)，点击或松开轮盘快捷键执行")
    }

    private var centerLabel: some View {
        Button(action: onDismiss) {
            HStack(spacing: 7) {
                if let selectedItem {
                    RadialActionIcon(item: selectedItem, size: 20, selected: false, showsTile: false)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(selectedItem?.title ?? "移动选择")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 82, minHeight: 31)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.38), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
            .animation(.snappy(duration: 0.18), value: interaction.selectedItemID)
        }
        .buttonStyle(.plain)
        .opacity(interaction.isPresented ? 1 : 0)
        .scaleEffect(interaction.isPresented ? 1 : 0.82)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: interaction.isPresented)
        .help("关闭轮盘")
        .accessibilityLabel(selectedItem == nil ? "关闭快速启动轮盘" : selectedItem!.title)
    }

    private var selectedItem: RadialMenuItem? {
        interaction.items.first { $0.id == interaction.selectedItemID }
    }

    private func updateDirectionalSelection(_ phase: HoverPhase) {
        switch phase {
        case let .active(location):
            let deltaX = location.x - canvasSize / 2
            let deltaY = location.y - canvasSize / 2
            let distance = hypot(deltaX, deltaY)
            guard distance >= deadZoneRadius, !interaction.items.isEmpty else {
                interaction.selectedItemID = nil
                return
            }

            let angle = atan2(deltaY, deltaX) * 180 / .pi
            let clockwiseFromTop = (angle + 90 + 360).truncatingRemainder(dividingBy: 360)
            let step = 360 / Double(interaction.items.count)
            let index = Int((clockwiseFromTop / step).rounded()) % interaction.items.count
            let id = interaction.items[index].id
            if interaction.selectedItemID != id {
                interaction.selectedItemID = id
                store.radialSelectionDetent()
            }

        case .ended:
            interaction.selectedItemID = nil
        }
    }
}

struct RadialActionIcon: View {
    let item: RadialMenuItem
    let size: CGFloat
    let selected: Bool
    var showsTile = true

    var body: some View {
        Group {
            if usesApplicationIcon, let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(showsTile ? 2 : 0)
            } else {
                RadialIconView(
                    value: item.systemImage,
                    size: iconSize,
                    systemColor: showsTile ? .white : tint
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(localIconPadding)
                    .background {
                        if showsTile {
                            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(0.9), tint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: showsTile ? size * 0.25 : size * 0.18, style: .continuous))
        .overlay {
            if showsTile {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(
                        selected ? Color.white.opacity(0.9) : Color.white.opacity(0.28),
                        lineWidth: selected ? 1.6 : 0.75
                    )
            }
        }
    }

    private var iconReference: RadialIconReference {
        RadialIconReference(rawValue: item.systemImage)
    }

    private var usesApplicationIcon: Bool {
        guard case let .system(symbol) = iconReference else { return false }
        return symbol == "app.fill" || symbol == "macwindow"
    }

    private var iconSize: CGFloat {
        switch iconReference {
        case .emoji: size * 0.56
        case .local: size
        case .system: size * 0.45
        }
    }

    private var localIconPadding: CGFloat {
        if case .local = iconReference { return showsTile ? 0 : 1 }
        return 0
    }

    private var appIcon: NSImage? {
        let path: String
        switch item.action {
        case let .application(value), let .systemApplication(value):
            path = value
        default:
            return nil
        }
        guard !path.isEmpty else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private var tint: Color {
        switch item.action.kind {
        case .unconfigured: .gray
        case .codexToolbox: .indigo
        case .keyboardShortcut: .blue
        case .application: .cyan
        case .systemApplication: .blue
        case .plugin: .purple
        case .website: .teal
        case .pasteText: .orange
        case .folder: .yellow
        case .shortcut: .pink
        }
    }
}
