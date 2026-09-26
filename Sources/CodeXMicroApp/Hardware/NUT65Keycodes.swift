import Foundation

enum NUT65Keycodes {
    struct Item: Identifiable { let code: UInt16; let title: String; var id: UInt16 { code } }
    static let items: [Item] = makeItems()

    private static func makeItems() -> [Item] {
        var result = [Item(code: 0, title: "禁用此键"), Item(code: 1, title: "透明（继承下层）")]
        result += (0..<26).map { Item(code: UInt16(4 + $0), title: String(UnicodeScalar(65 + $0)!)) }
        result += (0..<10).map { Item(code: UInt16(30 + $0), title: String(($0 + 1) % 10)) }
        let typing: [(UInt16, String)] = [(40,"Enter"),(41,"Esc"),(42,"Backspace"),(43,"Tab"),(44,"Space"),
            (45,"-"),(46,"="),(47,"["),(48,"]"),(49,"\\"),(51,";"),(52,"'"),(53,"`"),(54,","),(55,"."),(56,"/"),(57,"Caps Lock")]
        let navigation: [(UInt16, String)] = [(70,"Print Screen"),(71,"Scroll Lock"),(72,"Pause"),(73,"Insert"),(74,"Home"),
            (75,"Page Up"),(76,"Delete"),(77,"End"),(78,"Page Down"),(79,"→"),(80,"←"),(81,"↓"),(82,"↑"),(101,"Menu")]
        let media: [(UInt16, String)] = [(168,"静音"),(169,"音量＋"),(170,"音量－"),(171,"下一首"),
            (172,"上一首"),(173,"停止播放"),(174,"播放／暂停")]
        let modifiers: [(UInt16, String)] = [(224,"左 Control"),(225,"左 Shift"),(226,"左 Option"),(227,"左 Command"),
            (228,"右 Control"),(229,"右 Shift"),(230,"右 Option"),(231,"右 Command"),(0x7c16,"Esc / ~")]
        for group in [typing, navigation, media, modifiers] {
            result.append(contentsOf: group.map { Item(code: $0.0, title: $0.1) })
        }
        result += (0..<12).map { Item(code: UInt16(58 + $0), title: "F\($0 + 1)") }
        result += (0..<12).map { Item(code: UInt16(104 + $0), title: "F\($0 + 13)") }
        return result
    }
    static func title(_ code: UInt16) -> String {
        if let item = items.first(where: { $0.code == code }) { return item.title }
        if (0x5220..<0x5230).contains(code) { return "Fn → 层 \(code - 0x5220)" }
        if (0x0100...0x0fff).contains(code), let key = items.first(where: { $0.code == code & 255 }) {
            let modifiers = [(UInt16(0x0100),"⌃"),(0x0200,"⇧"),(0x0400,"⌥"),(0x0800,"⌘")]
            return modifiers.filter { code & $0.0 != 0 }.map(\.1).joined() + key.title
        }
        return String(format: "0x%04X", code)
    }
}
