import AppKit

@MainActor
enum EditCommands {
    static func action(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              key.count == 1
        else {
            return nil
        }
        let shift = flags.contains(.shift)
        switch key {
        case "a" where !shift:
            return #selector(NSText.selectAll(_:))
        case "x" where !shift:
            return #selector(NSText.cut(_:))
        case "c" where !shift:
            return #selector(NSText.copy(_:))
        case "v" where !shift:
            return #selector(NSText.paste(_:))
        case "z" where !shift:
            return Selector(("undo:"))
        case "z" where shift:
            return Selector(("redo:"))
        default:
            return nil
        }
    }

    static func menu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(item(String(localized: "Undo"), Selector(("undo:")), "z"))
        menu.addItem(item(String(localized: "Redo"), Selector(("redo:")), "Z"))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(String(localized: "Delete"), #selector(NSText.delete(_:)), ""))
        menu.addItem(item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = nil
        return entry
    }
}
