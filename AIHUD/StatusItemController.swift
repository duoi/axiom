import AppKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = EndpointStore()
    private lazy var hud = HUDController(store: store)
    private let debugItem = NSMenuItem(title: String(localized: "Debug"), action: #selector(debug), keyEquivalent: "")

    func start() {
        item.button?.image = Self.statusImage()
        item.button?.image?.isTemplate = true
        item.button?.setAccessibilityLabel(String(localized: "Axiom"))
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: String(localized: "Show"), action: #selector(show), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(localized: "Settings"), action: #selector(settings), keyEquivalent: ","))
        menu.addItem(debugItem)
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit"), action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items {
            entry.target = self
        }
        item.menu = menu
        installMainMenu()
        hud.statusItemFrame = item.button?.window?.frame
        KeyboardShortcuts.onKeyUp(for: .toggleHUD) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.hud.toggle()
                }
            }
        }
        if !DebugRouting.enabled(by: CommandLine.arguments) {
            hud.startVoiceIfNeeded()
        }
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: String(localized: "Axiom"))
        appItem.submenu = appMenu
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: String(localized: "Quit Axiom"), action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        appMenu.addItem(quitItem)

        let editItem = NSMenuItem()
        main.addItem(editItem)
        editItem.submenu = EditCommands.menu()
        NSApp.mainMenu = main
    }

    func showFromLaunch() {
        show()
        #if DEBUG
        if let prompt = DebugRouting.demoPrompt(from: CommandLine.arguments) {
            Task { await hud.model.typeDemoPrompt(prompt) }
        }
        #endif
        if let command = DebugRouting.initialCommand(from: CommandLine.arguments),
           let parsed = DebugRouting.parse(command),
           DebugRouting.liveStreamText(for: parsed) != nil {
            hud.applyDebugCommand(command)
        }
    }

    func openSettingsFromLaunch() {
        settings()
    }

    func openDebugFromLaunch(command: String? = nil) {
        hud.statusItemFrame = item.button?.window?.frame
        hud.openDebug()
        if let command {
            hud.applyDebugCommand(command)
        }
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        debugItem.isHidden = !store.showsDebug()
    }

    @objc private func debug() {
        hud.statusItemFrame = item.button?.window?.frame
        hud.openDebug()
    }

    @objc private func quit() {
        hud.shutdown()
        NSApp.terminate(nil)
    }

    private static func statusImage() -> NSImage? {
        guard let original = NSImage(named: "AxiomLogo") else { return nil }
        let image = original.copy() as? NSImage ?? original
        image.isTemplate = true
        let height: CGFloat = 16
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : (860 / 663)
        image.size = NSSize(width: height * aspect, height: height)
        return image
    }
}
