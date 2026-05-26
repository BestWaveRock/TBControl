import AppKit

class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let ipcClient = IPCClient()
    private var status: StatusInfo?
    private var refreshTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupMenu()
        startRefresh()
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Turbo Boost 状态: —", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "CPU 温度: —", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "风扇转速: —", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "CPU 负载: —", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let tbItem = NSMenuItem(title: "禁用 Turbo Boost", action: #selector(toggleTurboBoost), keyEquivalent: "t")
        tbItem.target = self
        menu.addItem(tbItem)

        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for title in ["手动模式", "自动(温度)", "自动(电池)"] {
            let item = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            modeMenu.addItem(item)
        }

        let modeItem = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func startRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refreshTimer?.fire()
    }

    @objc private func refresh() {
        guard let st = ipcClient.getStatus() else {
            updateMenuItems(tbState: nil, temp: nil, fan: nil, load: nil, mode: nil, message: nil)
            return
        }
        status = st
        updateMenuItems(tbState: st.tbEnabled, temp: st.cpuTemp, fan: st.fanSpeed, load: st.cpuLoad, mode: st.mode, message: nil)
    }

    private func updateMenuItems(tbState: Bool?, temp: Double?, fan: Int?, load: Double?, mode: String?, message: String?) {
        guard let menu = statusItem.menu else { return }

        if let msg = message {
            menu.items[0].title = "⚠️ \(msg)"
        } else if let enabled = tbState {
            menu.items[0].title = enabled ? "✅ Turbo Boost: 已启用" : "🚫 Turbo Boost: 已禁用"
        } else {
            menu.items[0].title = "⚠️ Turbo Boost: 无法连接"
        }

        if let t = temp, t > 0 {
            menu.items[1].title = String(format: "🌡 CPU 温度: %.1f°C", t)
        } else {
            menu.items[1].title = "🌡 CPU 温度: —"
        }

        if let f = fan, f > 0 {
            menu.items[2].title = "🌀 风扇: \(f) rpm"
        } else {
            menu.items[2].title = "🌀 风扇: —"
        }

        if let l = load, l > 0 {
            menu.items[3].title = String(format: "⚡ CPU 负载: %.1f%%", l)
        } else {
            menu.items[3].title = "⚡ CPU 负载: —"
        }

        if let enabled = tbState {
            menu.item(at: 5)?.isEnabled = true
            menu.item(at: 5)?.title = enabled ? "禁用 Turbo Boost" : "启用 Turbo Boost"
        } else {
            menu.item(at: 5)?.isEnabled = false
        }

        if let statusItemButton = statusItem.button {
            let icon = tbState == false ? "🧊" : (tbState == nil ? "⏳" : "🔥")
            statusItemButton.title = icon
            if let t = temp, t > 0 {
                statusItemButton.toolTip = String(format: "%.1f°C | %d rpm", t, fan ?? 0)
            } else {
                statusItemButton.toolTip = tbState == nil ? "未连接" : ""
            }
        }
    }

    @objc private func toggleTurboBoost() {
        guard let st = status else { return }
        statusItem.menu?.item(at: 5)?.isEnabled = false

        let newState = !st.tbEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ok = self.ipcClient.setTurboBoost(enabled: newState)
            DispatchQueue.main.async {
                self.statusItem.menu?.item(at: 5)?.isEnabled = true
                if ok {
                    self.refresh()
                    NSSound(named: "Tink")?.play()
                } else {
                    self.updateMenuItems(tbState: st.tbEnabled, temp: st.cpuTemp, fan: st.fanSpeed, load: st.cpuLoad, mode: st.mode, message: "操作失败，守护进程无权限")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.refresh()
                    }
                }
            }
        }
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        let mode: String
        switch sender.title {
        case "自动(温度)": mode = "auto_temp"
        case "自动(电池)": mode = "auto_battery"
        default: mode = "manual"
        }
        _ = ipcClient.setMode(mode)
        refresh()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
