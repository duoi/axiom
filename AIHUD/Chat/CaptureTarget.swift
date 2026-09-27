import Foundation

enum CaptureTarget: String, CaseIterable, Identifiable {
    case screen
    case window

    var id: String { rawValue }
    var title: String { self == .screen ? "Screen" : "Window" }
    var symbolName: String { self == .screen ? "macwindow" : "macwindow.on.rectangle" }
}
