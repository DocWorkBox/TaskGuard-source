import Foundation

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all
    case codexThreads
    case development
    case suggested
    case ports
    case protected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .codexThreads: return "Codex 线程"
        case .development: return "开发服务"
        case .suggested: return "疑似残留"
        case .ports: return "监听端口"
        case .protected: return "白名单"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "rectangle.grid.1x2"
        case .codexThreads: return "bubble.left.and.text.bubble.right"
        case .development: return "terminal"
        case .suggested: return "exclamationmark.triangle"
        case .ports: return "network"
        case .protected: return "lock.shield"
        }
    }
}
