import Foundation

// Physical positions from the manufacturer NUT65 layout (13357_58650).
struct NUT65Key: Identifiable, Sendable {
    let row: Int
    let column: Int
    let x: Double
    let y: Double
    let width: Double
    let label: String
    var id: Int { row * NUT65Protocol.columns + column }
}

enum NUT65Layout {
    static let keys: [NUT65Key] = [
        .init(row: 0, column: 0, x: 0.00, y: 0.00, width: 1.00, label: "Esc`"),
        .init(row: 0, column: 1, x: 1.10, y: 0.00, width: 1.00, label: "!1"),
        .init(row: 0, column: 2, x: 2.18, y: 0.00, width: 1.00, label: "@2"),
        .init(row: 0, column: 3, x: 3.25, y: 0.00, width: 1.00, label: "#3"),
        .init(row: 0, column: 4, x: 4.35, y: 0.00, width: 1.00, label: "$4"),
        .init(row: 0, column: 5, x: 5.40, y: 0.00, width: 1.00, label: "%5"),
        .init(row: 0, column: 6, x: 6.49, y: 0.00, width: 1.00, label: "^6"),
        .init(row: 0, column: 7, x: 7.58, y: 0.00, width: 1.00, label: "&7"),
        .init(row: 0, column: 8, x: 8.65, y: 0.00, width: 1.00, label: "*8"),
        .init(row: 0, column: 9, x: 9.76, y: 0.00, width: 1.00, label: "(9"),
        .init(row: 0, column: 10, x: 10.82, y: 0.00, width: 1.00, label: ")0"),
        .init(row: 0, column: 11, x: 11.90, y: 0.00, width: 1.00, label: "_-"),
        .init(row: 0, column: 12, x: 12.99, y: 0.00, width: 1.00, label: "+="),
        .init(row: 0, column: 13, x: 14.00, y: 0.00, width: 2.15, label: "Bksp"),
        .init(row: 0, column: 14, x: 16.25, y: 0.00, width: 1.00, label: "Ins"),
        .init(row: 1, column: 0, x: 0.00, y: 1.08, width: 1.60, label: "Tab"),
        .init(row: 1, column: 1, x: 1.65, y: 1.08, width: 1.00, label: "Q"),
        .init(row: 1, column: 2, x: 2.73, y: 1.08, width: 1.00, label: "W"),
        .init(row: 1, column: 3, x: 3.80, y: 1.08, width: 1.00, label: "E"),
        .init(row: 1, column: 4, x: 4.88, y: 1.08, width: 1.00, label: "R"),
        .init(row: 1, column: 5, x: 5.96, y: 1.08, width: 1.00, label: "T"),
        .init(row: 1, column: 6, x: 7.03, y: 1.08, width: 1.00, label: "Y"),
        .init(row: 1, column: 7, x: 8.12, y: 1.08, width: 1.00, label: "U"),
        .init(row: 1, column: 8, x: 9.20, y: 1.08, width: 1.00, label: "I"),
        .init(row: 1, column: 9, x: 10.28, y: 1.08, width: 1.00, label: "O"),
        .init(row: 1, column: 10, x: 11.35, y: 1.08, width: 1.00, label: "P"),
        .init(row: 1, column: 11, x: 12.43, y: 1.08, width: 1.00, label: "{["),
        .init(row: 1, column: 12, x: 13.50, y: 1.08, width: 1.00, label: "}]"),
        .init(row: 1, column: 13, x: 14.53, y: 1.08, width: 1.60, label: "|、"),
        .init(row: 1, column: 14, x: 16.25, y: 1.08, width: 1.00, label: "Del"),
        .init(row: 2, column: 0, x: 0.00, y: 2.15, width: 1.85, label: "CAPS"),
        .init(row: 2, column: 1, x: 1.93, y: 2.15, width: 1.00, label: "A"),
        .init(row: 2, column: 2, x: 3.00, y: 2.15, width: 1.00, label: "S"),
        .init(row: 2, column: 3, x: 4.07, y: 2.15, width: 1.00, label: "D"),
        .init(row: 2, column: 4, x: 5.14, y: 2.15, width: 1.00, label: "F"),
        .init(row: 2, column: 5, x: 6.21, y: 2.15, width: 1.00, label: "G"),
        .init(row: 2, column: 6, x: 7.31, y: 2.15, width: 1.00, label: "H"),
        .init(row: 2, column: 7, x: 8.39, y: 2.15, width: 1.00, label: "J"),
        .init(row: 2, column: 8, x: 9.47, y: 2.15, width: 1.00, label: "K"),
        .init(row: 2, column: 9, x: 10.55, y: 2.15, width: 1.00, label: "L"),
        .init(row: 2, column: 10, x: 11.64, y: 2.15, width: 1.00, label: ":;"),
        .init(row: 2, column: 11, x: 12.70, y: 2.15, width: 1.00, label: "“’"),
        .init(row: 2, column: 13, x: 13.70, y: 2.15, width: 2.45, label: "Enter"),
        .init(row: 2, column: 14, x: 16.25, y: 2.15, width: 1.00, label: "PgUp"),
        .init(row: 3, column: 0, x: 0.00, y: 3.19, width: 2.40, label: "LShft"),
        .init(row: 3, column: 2, x: 2.46, y: 3.19, width: 1.00, label: "Z"),
        .init(row: 3, column: 3, x: 3.53, y: 3.19, width: 1.00, label: "X"),
        .init(row: 3, column: 4, x: 4.63, y: 3.19, width: 1.00, label: "C"),
        .init(row: 3, column: 5, x: 5.69, y: 3.19, width: 1.00, label: "V"),
        .init(row: 3, column: 6, x: 6.77, y: 3.19, width: 1.00, label: "B"),
        .init(row: 3, column: 7, x: 7.85, y: 3.19, width: 1.00, label: "N"),
        .init(row: 3, column: 8, x: 8.95, y: 3.19, width: 1.00, label: "M"),
        .init(row: 3, column: 9, x: 10.01, y: 3.19, width: 1.00, label: "<,"),
        .init(row: 3, column: 10, x: 11.09, y: 3.19, width: 1.00, label: ">."),
        .init(row: 3, column: 11, x: 12.16, y: 3.19, width: 1.00, label: "?/"),
        .init(row: 3, column: 12, x: 13.30, y: 3.19, width: 1.65, label: "RShft"),
        .init(row: 3, column: 13, x: 15.10, y: 3.19, width: 1.00, label: "↑"),
        .init(row: 3, column: 14, x: 16.25, y: 3.19, width: 1.00, label: "PgDn"),
        .init(row: 4, column: 0, x: 0.00, y: 4.28, width: 1.30, label: "LCTL"),
        .init(row: 4, column: 1, x: 1.35, y: 4.28, width: 1.30, label: "LWin"),
        .init(row: 4, column: 2, x: 2.65, y: 4.28, width: 1.30, label: "LAlt"),
        .init(row: 4, column: 5, x: 4.05, y: 4.28, width: 6.75, label: "Space"),
        .init(row: 4, column: 10, x: 10.82, y: 4.28, width: 1.30, label: "RAlt"),
        .init(row: 4, column: 11, x: 12.10, y: 4.28, width: 1.30, label: "FN"),
        .init(row: 4, column: 12, x: 14.02, y: 4.28, width: 1.00, label: "←"),
        .init(row: 4, column: 13, x: 15.10, y: 4.28, width: 1.00, label: "↓"),
        .init(row: 4, column: 14, x: 16.25, y: 4.28, width: 1.00, label: "→"),
    ]
}
