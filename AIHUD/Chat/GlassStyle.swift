import Foundation

enum GlassStyle: String, CaseIterable, Identifiable, Sendable {
    case clear
    case regular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .regular: "Regular"
        }
    }
}
