import Foundation

enum PanelPosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: Self { self }

    var label: String {
        switch self {
        case .top: "置顶模式"
        case .bottom: "沉底模式"
        }
    }

    var description: String {
        switch self {
        case .top: "悬浮于所有应用页面之上。"
        case .bottom: "沉底于所有应用页面之下。"
        }
    }
}
