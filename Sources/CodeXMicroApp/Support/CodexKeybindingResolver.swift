import Foundation

struct CodexKeybindingResolver {
    private struct Entry: Decodable {
        let command: String
        let key: String
    }

    let configurationURL: URL

    init(configurationURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/keybindings.json")) {
        self.configurationURL = configurationURL
    }

    func binding(
        for command: String,
        fallback: KeyboardShortcutBinding
    ) -> KeyboardShortcutBinding {
        guard
            let data = try? Data(contentsOf: configurationURL),
            let entries = try? JSONDecoder().decode([Entry].self, from: data),
            let key = entries.last(where: { $0.command == command })?.key,
            let binding = Self.parse(key)
        else {
            return fallback
        }
        return binding
    }

    static func parse(_ value: String) -> KeyboardShortcutBinding? {
        let parts = value.split(separator: "+").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let keyPart = parts.last, !keyPart.isEmpty else { return nil }

        var modifiers: ShortcutModifiers = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmd", "command", "meta": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }

        guard let keyCode = ShortcutKeyCatalog.keyCode(for: keyPart) else { return nil }
        return KeyboardShortcutBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            keyLabel: ShortcutKeyCatalog.label(for: keyCode) ?? keyPart.uppercased()
        )
    }
}
