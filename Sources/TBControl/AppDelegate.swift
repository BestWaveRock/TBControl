import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarController: MenuBarController?
    private var mainWindow: NSWindow?
    private let viewModel = MainWindowViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        menuBarController?.appDelegate = self
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let client = IPCClient()
        _ = client.sendCommand(["cmd": "quit"])
    }

    private func setupMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "TBControl")
        appMenu.addItem(withTitle: "About TBControl", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide TBControl", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit TBControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        winMenu.addItem(NSMenuItem.separator())
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu
        mainMenu.addItem(winItem)

        NSApp.mainMenu = mainMenu
    }

    func setupMainWindow() {
        if mainWindow == nil {
            let contentView = MainWindowView(viewModel: viewModel)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TBControl"
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.contentView = NSHostingView(rootView: contentView)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            self.mainWindow = window
        }
    }

    func showMainWindow() {
        setupMainMenu()
        setupMainWindow()
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == mainWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
