import SwiftUI

struct ShortcutMenuContent: View {
    @ObservedObject var store: CodexStore
    let target: ShortcutTarget

    var body: some View {
        Button {
            store.beginShortcutRecording(for: target)
        } label: {
            Label("设置快捷键…", systemImage: "keyboard")
        }

        if let shortcut = store.shortcut(for: target) {
            Divider()
            Text("当前：\(shortcut.displayName)")
            Button(role: .destructive) {
                store.clearShortcut(for: target)
            } label: {
                Label("清除快捷键", systemImage: "delete.left")
            }
        }
    }
}

private struct ShortcutConfigurableModifier: ViewModifier {
    @ObservedObject var store: CodexStore
    let target: ShortcutTarget

    func body(content: Content) -> some View {
        content.contextMenu {
            ShortcutMenuContent(store: store, target: target)
        }
    }
}

extension View {
    func shortcutConfigurable(_ target: ShortcutTarget, store: CodexStore) -> some View {
        modifier(ShortcutConfigurableModifier(store: store, target: target))
    }
}
