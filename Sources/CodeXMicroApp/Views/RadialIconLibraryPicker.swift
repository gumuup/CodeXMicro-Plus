import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RadialIconLibraryPicker: View {
    @Binding var selection: String

    @State private var source: Source = .emoji
    @State private var query = ""
    @State private var categoryID = RadialEmojiCatalog.categories.first?.id ?? "people"
    @State private var localEntries: [RadialCustomIconEntry] = []
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 42), spacing: 7)]

    var body: some View {
        VStack(spacing: 10) {
            Picker("图标来源", selection: $source) {
                ForEach(Source.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if source != .local {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(source == .emoji ? "输入名称搜索" : "搜索图标名称", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12))
                }
            }

            Divider()

            switch source {
            case .emoji:
                catalogView(categories: RadialEmojiCatalog.categories.map { ($0.id, $0.title) }) {
                    emojiGrid
                }
            case .symbols:
                catalogView(categories: RadialSymbolCatalog.categories.map { ($0.id, $0.title) }) {
                    symbolGrid
                }
            case .local:
                localView
            }
        }
        .padding(12)
        .frame(width: 500, height: 470)
        .onAppear {
            localEntries = RadialCustomIconStore.entries()
            synchronizeCategory()
        }
        .onChange(of: source) { _, _ in
            query = ""
            synchronizeCategory()
        }
        .alert("无法导入图片", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "请选择有效的图片文件。")
        }
    }

    private func catalogView<Content: View>(
        categories: [(String, String)],
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(categories, id: \.0) { category in
                        Button {
                            categoryID = category.0
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(categoryID == category.0 ? Color.accentColor : Color.secondary.opacity(0.42))
                                    .frame(width: 6, height: 6)
                                Text(category.1)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(categoryID == category.0 ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 27)
                            .background(
                                categoryID == category.0 ? Color.accentColor.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(width: 112)

            Divider()
                .padding(.leading, 7)

            content()
                .padding(.leading, 10)
        }
    }

    private var emojiGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(filteredEmojis, id: \.self) { emoji in
                    iconButton(value: RadialIconReference.emoji(emoji).rawValue, help: emoji) {
                        Text(emoji)
                            .font(.system(size: 23))
                    }
                }
            }
            .padding(2)
        }
    }

    private var symbolGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(filteredSymbols, id: \.self) { symbol in
                    iconButton(value: symbol, help: symbol) {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .medium))
                    }
                }
            }
            .padding(2)
        }
    }

    private var localView: some View {
        VStack(spacing: 12) {
            Button(action: chooseLocalImage) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 28, weight: .medium))
                    Text("选择本地图片")
                        .font(.headline)
                    Text("建议图片比例为 1:1，支持 jpg、jpeg、png、heic、webp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 105)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
            }
            .buttonStyle(.plain)

            if localEntries.isEmpty {
                ContentUnavailableView(
                    "暂无本地图标",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("导入后会保存在本机，并可在所有轮盘预设中使用。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(localEntries) { entry in
                            iconButton(
                                value: RadialIconReference.local(entry.filename).rawValue,
                                help: entry.filename
                            ) {
                                if let image = entry.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
    }

    private func iconButton<Content: View>(
        value: String,
        help: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            selection = value
        } label: {
            content()
                .frame(width: 36, height: 34)
                .clipped()
                .background(selection == value ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selection == value ? Color.accentColor : Color.primary.opacity(0.07))
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var filteredEmojis: [String] {
        RadialEmojiCatalog.search(query, categoryID: query.isEmpty ? categoryID : nil)
    }

    private var filteredSymbols: [String] {
        RadialSymbolCatalog.search(query, categoryID: query.isEmpty ? categoryID : nil)
    }

    private func synchronizeCategory() {
        let categories = source == .symbols ? RadialSymbolCatalog.categories.map(\.id) : RadialEmojiCatalog.categories.map(\.id)
        if !categories.contains(categoryID) {
            categoryID = categories.first ?? ""
        }
    }

    private func chooseLocalImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "选择用作轮盘图标的本地图片"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let entry = try RadialCustomIconStore.importImage(from: url)
            localEntries = RadialCustomIconStore.entries()
            selection = entry.token
        } catch {
            importError = error.localizedDescription
        }
    }

    private enum Source: String, CaseIterable, Identifiable {
        case emoji
        case symbols
        case local

        var id: String { rawValue }

        var title: String {
            switch self {
            case .emoji: "Emoji"
            case .symbols: "图标"
            case .local: "本地"
            }
        }
    }
}
