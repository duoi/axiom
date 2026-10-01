import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleHUD = Self("toggleHUD", default: .init(.k, modifiers: [.control, .option]))
    static let hideCard = Self("hideCard", default: .init(.escape))
    static let send = Self("send", default: .init(.return))
    static let newline = Self("newline", default: .init(.return, modifiers: [.option]))
    static let newlineShift = Self("newlineShift", default: .init(.return, modifiers: [.shift]))
    static let cyclePreset = Self("cyclePreset", default: .init(.a, modifiers: [.control]))
    static let cycleCapture = Self("cycleCapture", default: .init(.s, modifiers: [.control]))
    static let addContext = Self("addContext", default: .init(.c, modifiers: [.control]))
    static let toggleIncognito = Self("toggleIncognito", default: .init(.r, modifiers: [.control]))
    static let toggleDictation = Self("toggleDictation", default: .init(.quote, modifiers: [.control]))
}

enum CardShortcutBindings {
    static func current() -> [HUDShortcut: [BoundShortcut]] {
        var map: [HUDShortcut: [BoundShortcut]] = [:]
        func add(_ kind: HUDShortcut, _ name: KeyboardShortcuts.Name) {
            guard let shortcut = KeyboardShortcuts.Shortcut(name: name),
                  let bound = BoundShortcut(shortcut)
            else { return }
            map[kind, default: []].append(bound)
        }
        add(.hide, .hideCard)
        add(.send, .send)
        add(.newline, .newline)
        add(.newline, .newlineShift)
        add(.cyclePreset, .cyclePreset)
        add(.cycleCapture, .cycleCapture)
        add(.addContext, .addContext)
        add(.toggleIncognito, .toggleIncognito)
        add(.toggleDictation, .toggleDictation)
        return map
    }

    @MainActor
    static func label(for name: KeyboardShortcuts.Name) -> String {
        KeyboardShortcuts.Shortcut(name: name)?.description ?? ""
    }
}

extension BoundShortcut {
    init?(_ shortcut: KeyboardShortcuts.Shortcut) {
        let flags = shortcut.modifiers
        self.init(
            keyCode: UInt16(shortcut.carbonKeyCode),
            control: flags.contains(.control),
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift)
        )
    }
}
