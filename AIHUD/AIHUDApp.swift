import AppKit

@main
enum AIHUDMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        let controller = StatusItemController()
        status = controller
        controller.start()
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.async {
                controller.showFromLaunch()
            }
        }
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async {
                controller.openSettingsFromLaunch()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        status?.shutdown()
    }
}
