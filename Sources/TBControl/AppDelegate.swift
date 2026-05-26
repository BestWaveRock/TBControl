import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let client = IPCClient()
        _ = client.sendCommand(["cmd": "quit"])
    }
}
