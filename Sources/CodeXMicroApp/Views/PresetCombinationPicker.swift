import SwiftUI

/// Shared by radial menus and per-device hardware layouts.
struct PresetCombinationPicker: View {
    let selectedIndex: Int
    var count: Int = RadialMenuProfile.presetCombinationCount
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("预设组合")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("自动保存 · \(selectedIndex + 1)/\(count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    let isSelected = selectedIndex == index
                    Button {
                        onSelect(index)
                    } label: {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 23)
                            .background(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                        lineWidth: 0.75
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help("切换到预设组合 \(index + 1)")
                    .accessibilityLabel("预设组合 \(index + 1)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
        }
    }

}
