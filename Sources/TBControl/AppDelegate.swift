import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var mainWindow: NSWindow?
    private let viewModel = MainWindowViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        menuBarController?.appDelegate = self // We will add a weak reference to open the window
        
        setupMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let client = IPCClient()
        _ = client.sendCommand(["cmd": "quit"])
    }
    
    func setupMainWindow() {
        if mainWindow == nil {
            let contentView = MainWindowView(viewModel: viewModel)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TBControl"
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.contentView = NSHostingView(rootView: contentView)
            window.isReleasedWhenClosed = false
            self.mainWindow = window
        }
    }
    
    func showMainWindow() {
        setupMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
