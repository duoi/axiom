import Foundation

enum CaptureTarget: String, CaseIterable, Identifiable {
    case screen
    case window

    var id: String { rawValue }
    var title: String {
        self == .screen ? String(localized: "Screen") : String(localized: "Window")
    }
    var symbolName: String { self == .screen ? "macwindow" : "macwindow.on.rectangle" }
}
