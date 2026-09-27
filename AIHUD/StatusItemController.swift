import AppKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = EndpointStore()
    private lazy var hud = HUDController(store: store)

    func start() {
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "AI HUD")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show", action: #selector(show), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(settings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items {
            entry.target = self
        }
        item.menu = menu
        hud.statusItemFrame = item.button?.window?.frame
        KeyboardShortcuts.onKeyUp(for: .toggleHUD) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.hud.toggle()
                }
            }
        }
    }

    func showFromLaunch() {
        show()
    }

    func shutdown() {
        hud.shutdown()
    }

    @objc private func show() {
        hud.statusItemFrame = item.button?.window?.frame
        hud.show()
    }

    @objc private func settings() {
        hud.statusItemFrame = item.button?.window?.frame
        hud.openSettings()
    }

    @objc private func quit() {
        hud.shutdown()
        NSApp.terminate(nil)
    }
}
