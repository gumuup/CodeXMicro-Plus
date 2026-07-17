import SwiftUI

struct ToolboxView: View {
    let onSelect: (ToolboxAction) -> Void

    @State private var query = ""
    @State private var category: ToolboxCategory = .all

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField
            categoryPicker

            HStack {
                Text("\(filteredActions.count) 个功能")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                legend
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredActions) { action in
                        ToolboxKeyButton(action: action) {
                            onSelect(action)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
        }
        .padding(18)
        .frame(width: 640, height: 520)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 32, height: 32)
                .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 工具箱")
                    .font(.headline)
                Text("官方快捷键、入口与常用一键工作流")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索功能、键帽或分类", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(ToolboxCategory.allCases) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            category = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(category == item ? .white : .primary.opacity(0.72))
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(
                                category == item ? Color.indigo : Color.primary.opacity(0.055),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var legend: some View {
        HStack(spacing: 9) {
            LegendDot(color: .blue, text: "快捷键")
            LegendDot(color: .purple, text: "入口")
            LegendDot(color: .orange, text: "工作流")
        }
    }

    private var filteredActions: [ToolboxAction] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ToolboxAction.allCases.filter { action in
            let categoryMatches = category == .all || action.category == category
            let queryMatches = normalizedQuery.isEmpty || action.searchText.contains(normalizedQuery)
            return categoryMatches && queryMatches
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ToolboxKeyButton: View {
    let action: ToolboxAction
    let perform: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                    Spacer()
                    Text(action.keycap)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(action.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(action.detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
            .background(
                isHovered ? accent.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isHovered ? accent.opacity(0.38) : Color.primary.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0.045), radius: isHovered ? 5 : 2, y: 2)
            .scaleEffect(isHovered ? 1.015 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(action.title) · \(action.kind.label)")
        .accessibilityLabel(action.title)
        .accessibilityHint(action.kind.label)
    }

    private var accent: Color {
        switch action.kind {
        case .shortcut: .blue
        case .destination: .purple
        case .workflow: .orange
        }
    }
}
