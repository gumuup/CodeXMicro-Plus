import AppKit
import SwiftUI

struct ClipboardSidebarView: View {
    @ObservedObject var history: ClipboardHistoryStore
    let onSelect: (ClipboardHistoryItem) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var searchIsFocused: Bool

    private var filteredItems: [ClipboardHistoryItem] {
        guard !query.isEmpty else { return history.items }
        return history.items.filter {
            $0.searchableText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索近期复制内容", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭剪贴板侧栏")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.thinMaterial)

            Divider()

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "暂无剪贴板记录" : "没有搜索结果",
                    systemImage: query.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(query.isEmpty ? "复制的文字和图片会显示在这里" : "试试其他关键词")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            ClipboardHistoryCard(item: item) {
                                onSelect(item)
                            }
                            .contextMenu {
                                Button("复制") { _ = history.restore(item) }
                                Button("删除", role: .destructive) { history.delete(item) }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 8)
        .padding(10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchIsFocused = true
            }
        }
        .onExitCommand(perform: onDismiss)
    }
}

private struct ClipboardHistoryCard: View {
    let item: ClipboardHistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                content
                HStack(spacing: 6) {
                    ApplicationIcon(bundleIdentifier: item.sourceBundleIdentifier)
                    Text(item.sourceApplicationName ?? "未知来源")
                        .lineLimit(1)
                    Spacer()
                    Text(item.createdAt, format: .relative(presentation: .named))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case let .text(value):
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .textSelection(.enabled)
        case let .image(data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }
}

private struct ApplicationIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: 16, height: 16)
    }

    private var image: NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
