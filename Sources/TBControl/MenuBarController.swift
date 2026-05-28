import AppKit
import UserNotifications
import OSLog

class MenuBarController: NSObject, UNUserNotificationCenterDelegate, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let ipcClient = IPCClient()
    private var status: StatusInfo?
    private var refreshTimer: Timer?
    private let githubRepo = "https://api.github.com/repos/BestWaveRock/TBControl/releases/latest"
    private var latestVersion: String?
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let logger = OSLog(subsystem: "com.tbcontrol.app", category: "UI")
    private var touchBarController: TouchBarController?
    private var isTouchBarEnabled = false
    private var lastVersionCheck: Date?
    weak var appDelegate: AppDelegate?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupMenu()
        setupNotifications()
        startRefresh()
        checkVersion()
        
        NotificationCenter.default.addObserver(self, selector: #selector(autoLaunchChanged), name: NSNotification.Name("AutoLaunchChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(touchBarConfigChanged), name: NSNotification.Name("TouchBarConfigChanged"), object: nil)
        
        // Initial setup for Touch Bar
        isTouchBarEnabled = UserDefaults.standard.bool(forKey: "isTouchBarEnabled")
        if isTouchBarEnabled {
            setupTouchBar()
        }
    }

    @objc private func autoLaunchChanged() {
        updateAutoLaunchMenuItem()
    }
    
    @objc private func touchBarConfigChanged() {
        let enabled = UserDefaults.standard.bool(forKey: "isTouchBarEnabled")
        if enabled != isTouchBarEnabled {
            toggleTouchBarAction()
        } else if isTouchBarEnabled {
            // Re-setup touch bar to apply new layout
            setupTouchBar()
        }
    }

    @objc private func toggleTouchBarAction() {
        isTouchBarEnabled.toggle()
        UserDefaults.standard.set(isTouchBarEnabled, forKey: "isTouchBarEnabled")
        
        if isTouchBarEnabled {
            setupTouchBar()
        } else {
            removeTouchBar()
        }
        statusItem.menu?.item(withTag: 201)?.state = isTouchBarEnabled ? .on : .off
    }
    
    private func setupTouchBar() {
        // Remove existing first if any
        removeTouchBar()
        
        let controller = TouchBarController()
        self.touchBarController = controller
        
        controller.onToggleTurbo = { [weak self] in
            self?.toggleTurboBoost()
        }
        
        controller.onToggleMode = { [weak self] in
            guard let self = self, let currentMode = self.status?.mode else { return }
            let modes = ["manual", "auto_temp", "auto_battery", "auto_load", "auto_fan"]
            if let index = modes.firstIndex(of: currentMode) {
                let nextIndex = (index + 1) % modes.count
                let nextMode = modes[nextIndex]
                _ = self.ipcClient.setMode(nextMode)
                self.refresh()
            }
        }
        
        let touchBar = controller.makeTouchBar()
        
        if #available(macOS 10.12.2, *) {
            NSTouchBar.presentSystemModalFunctionBar(touchBar, placement: 1, systemTrayItemIdentifier: .statsItem)
        }
        refresh()
    }
    
    private func removeTouchBar() {
        if let controller = touchBarController, let touchBar = controller.touchBar {
            if #available(macOS 10.12.2, *) {
                NSTouchBar.dismissSystemModalFunctionBar(touchBar)
            }
            if let item = touchBar.item(forIdentifier: .statsItem) {
                NSTouchBarItem.removeSystemTrayItem(item)
            }
        }
        self.touchBarController = nil
    }

    @objc private func toggleTouchBar() {
        toggleTouchBarAction()
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                os_log("Notification permission error: %@", type: .error, error.localizedDescription)
            }
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let openMainItem = NSMenuItem(title: "打开主窗口...", action: #selector(openMainWindow), keyEquivalent: "o")
        openMainItem.target = self
        menu.addItem(openMainItem)

        menu.addItem(.separator())

        let tbStatusItem = NSMenuItem(title: "Turbo Boost 状态: —", action: nil, keyEquivalent: "")
        tbStatusItem.tag = 10
        menu.addItem(tbStatusItem)

        let tempItem = NSMenuItem(title: "CPU 温度: —", action: nil, keyEquivalent: "")
        tempItem.tag = 11
        menu.addItem(tempItem)

        let fanItem = NSMenuItem(title: "风扇转速: —", action: nil, keyEquivalent: "")
        fanItem.tag = 12
        menu.addItem(fanItem)

        let loadItem = NSMenuItem(title: "CPU 负载: —", action: nil, keyEquivalent: "")
        loadItem.tag = 13
        menu.addItem(loadItem)
        
        let modeDisplayItem = NSMenuItem(title: "当前模式: —", action: nil, keyEquivalent: "")
        modeDisplayItem.tag = 14
        menu.addItem(modeDisplayItem)

        menu.addItem(.separator())

        let tbToggleItem = NSMenuItem(title: "禁用 Turbo Boost", action: #selector(toggleTurboBoost), keyEquivalent: "t")
        tbToggleItem.target = self
        tbToggleItem.tag = 15
        menu.addItem(tbToggleItem)

        menu.addItem(.separator())

        let modeMenu = NSMenu()
        
        let manualItem = NSMenuItem(title: "手动模式", action: #selector(setMode(_:)), keyEquivalent: "")
        manualItem.target = self
        modeMenu.addItem(manualItem)
        
        let tempModeItem = NSMenuItem(title: "自动(温度)", action: #selector(setMode(_:)), keyEquivalent: "")
        tempModeItem.target = self
        modeMenu.addItem(tempModeItem)
        
        let battItem = NSMenuItem(title: "自动(电池)", action: #selector(setMode(_:)), keyEquivalent: "")
        battItem.target = self
        let battSub = NSMenu()
        for pct in [10, 20, 30, 40, 50] {
            let pctItem = NSMenuItem(title: "电量 <= \(pct)%", action: #selector(setBatteryThreshold(_:)), keyEquivalent: "")
            pctItem.target = self
            pctItem.tag = pct
            battSub.addItem(pctItem)
        }
        battItem.submenu = battSub
        modeMenu.addItem(battItem)
        
        let loadModeItem = NSMenuItem(title: "自动(负载)", action: #selector(setMode(_:)), keyEquivalent: "")
        loadModeItem.target = self
        modeMenu.addItem(loadModeItem)
        
        let fanModeItem = NSMenuItem(title: "自动(风扇)", action: #selector(setMode(_:)), keyEquivalent: "")
        fanModeItem.target = self
        modeMenu.addItem(fanModeItem)

        let modeItem = NSMenuItem(title: "模式设置", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        modeItem.tag = 16
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let autoLaunchItem = NSMenuItem(title: "开机自启", action: #selector(toggleAutoLaunch), keyEquivalent: "")
        autoLaunchItem.target = self
        autoLaunchItem.tag = 200
        menu.addItem(autoLaunchItem)
        
        let touchBarItem = NSMenuItem(title: "Touch Bar 监控", action: #selector(toggleTouchBar), keyEquivalent: "")
        touchBarItem.target = self
        touchBarItem.tag = 201
        touchBarItem.state = isTouchBarEnabled ? .on : .off
        menu.addItem(touchBarItem)

        let daemonStatusItem = NSMenuItem(title: "守护进程: 检测中...", action: nil, keyEquivalent: "")
        daemonStatusItem.tag = 100
        menu.addItem(daemonStatusItem)
        
        let installItem = NSMenuItem(title: "安装守护进程", action: #selector(installDaemon), keyEquivalent: "")
        installItem.target = self
        installItem.tag = 101
        installItem.isHidden = true
        menu.addItem(installItem)
        
        let uninstallItem = NSMenuItem(title: "彻底卸载组件", action: #selector(uninstallComponents), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(.separator())

        let versionItem = NSMenuItem(title: "版本: \(currentVersion)", action: #selector(openGitHub), keyEquivalent: "")
        versionItem.target = self
        versionItem.tag = 300
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
        updateAutoLaunchMenuItem()
    }

    @objc private func openMainWindow() {
        appDelegate?.showMainWindow()
    }

    // MARK: - NSMenuDelegate
    func menuWillOpen(_ menu: NSMenu) {
        // Check version when menu opens, but only if it's been more than 1 hour since last check
        if let last = lastVersionCheck, Date().timeIntervalSince(last) < 3600 {
            return
        }
        checkVersion()
    }

    private func checkVersion() {
        guard let url = URL(string: githubRepo) else { return }
        
        os_log("Checking for updates at %@", log: logger, type: .debug, githubRepo)
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Set last check time only after request completes to avoid blocking on instant network failures
            self.lastVersionCheck = Date()
            
            if let error = error {
                os_log("Version check network error: %@", log: self.logger, type: .error, error.localizedDescription)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                os_log("Failed to parse version JSON from GitHub", log: self.logger, type: .error)
                return
            }
            
            let latest = tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let current = self.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            self.latestVersion = latest
            
            os_log("Latest version: %@, Current version: %@", log: self.logger, type: .info, latest, current)
            
            DispatchQueue.main.async {
                if latest.compare(current, options: .numeric) == .orderedDescending {
                    os_log("New version available: %@", log: self.logger, type: .info, latest)
                    self.statusItem.menu?.item(withTag: 300)?.title = "⭕ 有新版本: v\(latest)"
                } else {
                    os_log("App is up to date", log: self.logger, type: .info)
                    self.statusItem.menu?.item(withTag: 300)?.title = "版本: \(current)"
                }
            }
        }.resume()
    }

    @objc private func openGitHub() {
        let urlStr = latestVersion != nil ? "https://github.com/BestWaveRock/TBControl/releases" : "https://github.com/BestWaveRock/TBControl"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    private func isAutoLaunchEnabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"System Events\" to get name of every login item"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("TBControl")
    }

    @objc private func toggleAutoLaunch() {
        let enabled = isAutoLaunchEnabled()
        let appPath = Bundle.main.bundlePath
        let script: String
        if enabled {
            script = "tell application \"System Events\" to delete login item \"TBControl\""
        } else {
            script = "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", name:\"TBControl\", hidden:false}"
        }
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        updateAutoLaunchMenuItem()
    }

    private func updateAutoLaunchMenuItem() {
        statusItem.menu?.item(withTag: 200)?.state = isAutoLaunchEnabled() ? .on : .off
    }

    func startRefresh() {
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        timer.fire()
    }

    private var lastNotifiedState: Bool?

    private func sendNotification(enabled: Bool, reason: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "Turbo Boost \(enabled ? "已启用" : "已禁用")"
        if let reason = reason {
            content.body = reason
        } else {
            content.body = enabled ? "CPU 已恢复满血状态" : "CPU 已进入降温节能模式"
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func uninstallComponents() {
        let alert = NSAlert()
        alert.messageText = "确定要卸载吗？"
        alert.informativeText = "这将会卸载内核扩展、守护进程及所有相关配置文件。App 将在卸载完成后退出。"
        alert.addButton(withTitle: "确定卸载")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let script = """
            do shell script "launchctl unload /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist 2>/dev/null || true; kextunload -b com.tbcontrol.DisableTurboBoost 2>/dev/null || true; rm -f /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist; rm -rf '/Library/Application Support/TBControl'; rm -f /var/log/tbcontrol.log; rm -f /tmp/tbcontrol.sock" with administrator privileges
            """
            
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
            
            if error == nil {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @objc private func refresh() {
        let isDaemonRunning = checkDaemonRunning()
        
        guard let st = ipcClient.getStatus() else {
            updateMenuItems(tbState: nil, temp: nil, fanSpeeds: nil, load: nil, mode: nil, message: nil, daemonRunning: isDaemonRunning)
            return
        }
        
        // Notify if state changed (usually by auto engine)
        if let last = lastNotifiedState, last != st.tbEnabled {
            let reason = st.mode == "manual" ? nil : "自动模式 (\(getModeName(st.mode))) 触发"
            sendNotification(enabled: st.tbEnabled, reason: reason)
        }
        lastNotifiedState = st.tbEnabled
        
        status = st
        updateMenuItems(tbState: st.tbEnabled, temp: st.cpuTemp, fanSpeeds: st.fanSpeeds, load: st.cpuLoad, mode: st.mode, message: nil, daemonRunning: isDaemonRunning)
        
        if isTouchBarEnabled {
            touchBarController?.updateStats(temp: st.cpuTemp, fanSpeeds: st.fanSpeeds, load: st.cpuLoad, tbEnabled: st.tbEnabled, battery: st.batteryLevel, mode: st.mode)
        }
    }

    private func getModeName(_ mode: String?) -> String {
        switch mode {
        case "auto_temp": return "温度"
        case "auto_battery": return "电池"
        case "auto_load": return "负载"
        case "auto_fan": return "风扇"
        case "manual": return "手动"
        default: return "未知"
        }
    }

    private func checkDaemonRunning() -> Bool {
        // 1. Check if the socket exists (best indicator of a running daemon)
        if FileManager.default.fileExists(atPath: "/tmp/tbcontrol.sock") {
            return true
        }

        // 2. Check process list for the daemon binary name
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "tbcontrold"]
        try? pgrep.run()
        pgrep.waitUntilExit()
        if pgrep.terminationStatus == 0 {
            return true
        }
        
        // 3. Check launchctl list for the label
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8), 
           (output.contains("com.tbcontrol.tbcontrold") || output.contains("com.tbcontrol.daemon")) {
            return true
        }
        
        return false
    }

    private func updateMenuItems(tbState: Bool?, temp: Double?, fanSpeeds: [Int]?, load: Double?, mode: String?, message: String?, daemonRunning: Bool) {
        guard let menu = statusItem.menu else { return }

        // Update Daemon Status Items
        menu.item(withTag: 100)?.title = daemonRunning ? "⚙️ 守护进程: 运行中" : "⚙️ 守护进程: 未安装/未运行"
        menu.item(withTag: 101)?.isHidden = daemonRunning

        if let msg = message {
            menu.item(withTag: 10)?.title = "⚠️ \(msg)"
        } else if let enabled = tbState {
            menu.item(withTag: 10)?.title = enabled ? "✅ Turbo Boost: 已启用" : "🚫 Turbo Boost: 已禁用"
        } else {
            menu.item(withTag: 10)?.title = "⚠️ Turbo Boost: 无法连接"
        }

        if let t = temp {
            menu.item(withTag: 11)?.title = String(format: "🌡 CPU 温度: %.1f°C", t)
        } else {
            menu.item(withTag: 11)?.title = "🌡 CPU 温度: —"
        }

        if let fans = fanSpeeds, !fans.isEmpty {
            let fanStr = fans.map { "\($0)" }.joined(separator: " / ")
            menu.item(withTag: 12)?.title = "🌀 风扇: \(fanStr) rpm"
        } else {
            menu.item(withTag: 12)?.title = "🌀 风扇: —"
        }

        if let l = load, l > 0 {
            menu.item(withTag: 13)?.title = String(format: "⚡ CPU 负载: %.1f%%", l)
        } else {
            menu.item(withTag: 13)?.title = "⚡ CPU 负载: —"
        }

        // Display current mode in primary menu
        let modeName: String
        switch mode {
        case "auto_temp": modeName = "自动(温度)"
        case "auto_battery": modeName = "自动(电池)"
        case "auto_load": modeName = "自动(负载)"
        case "auto_fan": modeName = "自动(风扇)"
        case "manual": modeName = "手动模式"
        default: modeName = "未知"
        }
        menu.item(withTag: 14)?.title = "🎯 当前模式: \(modeName)"

        if let enabled = tbState {
            menu.item(withTag: 15)?.isEnabled = true
            menu.item(withTag: 15)?.title = enabled ? "禁用 Turbo Boost" : "启用 Turbo Boost"
        } else {
            menu.item(withTag: 15)?.isEnabled = false
        }

        // Update mode menu checkmarks
        if let modeItem = menu.item(withTag: 16), let modeMenu = modeItem.submenu {
            for item in modeMenu.items {
                let itemMode: String
                switch item.title {
                case "手动模式": itemMode = "manual"
                case "自动(温度)": itemMode = "auto_temp"
                case "自动(电池)": itemMode = "auto_battery"
                case "自动(负载)": itemMode = "auto_load"
                case "自动(风扇)": itemMode = "auto_fan"
                default: itemMode = ""
                }
                item.state = (itemMode == mode) ? .on : .off
            }
        }

        if let statusItemButton = statusItem.button {
            let icon = tbState == false ? "🧊" : (tbState == nil ? "⏳" : "🔥")
            statusItemButton.title = icon
            if let t = temp {
                let fanStr = fanSpeeds?.map { "\($0)" }.joined(separator: "/") ?? "0"
                statusItemButton.toolTip = String(format: "%.1f°C | %@ rpm", t, fanStr)
            } else {
                statusItemButton.toolTip = tbState == nil ? "未连接" : ""
            }
        }
    }

    @objc private func toggleTurboBoost() {
        guard let st = status else { return }
        statusItem.menu?.item(withTag: 15)?.isEnabled = false

        let newState = !st.tbEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let resp = self.ipcClient.sendCommand(["cmd": "set_tb", "enabled": newState])
            let ok = resp?["success"] as? Bool ?? false
            let errorMsg = resp?["error"] as? String ?? "操作失败，守护进程无权限"

            DispatchQueue.main.async {
                self.statusItem.menu?.item(withTag: 15)?.isEnabled = true
                if ok {
                    self.lastNotifiedState = newState // Manual toggle, we'll notify here
                    self.sendNotification(enabled: newState)
                    self.refresh()
                    NSSound(named: "Tink")?.play()
                } else {
                    self.updateMenuItems(tbState: st.tbEnabled, temp: st.cpuTemp, fanSpeeds: st.fanSpeeds, load: st.cpuLoad, mode: st.mode, message: errorMsg, daemonRunning: self.checkDaemonRunning())
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
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
        case "自动(负载)": mode = "auto_load"
        case "自动(风扇)": mode = "auto_fan"
        default: mode = "manual"
        }
        _ = ipcClient.setMode(mode)
        refresh()
    }

    @objc private func setBatteryThreshold(_ sender: NSMenuItem) {
        let threshold = sender.tag
        _ = ipcClient.setMode("auto_battery", config: ["battery_threshold": threshold])
        refresh()
    }

    @objc private func installDaemon() {
        guard let daemonPath = Bundle.main.path(forResource: "tbcontrold", ofType: nil),
              let kextPath = Bundle.main.path(forResource: "DisableTurboBoost", ofType: "kext") else {
            let alert = NSAlert()
            alert.messageText = "错误"
            alert.informativeText = "无法在 App 包内找到必要组件。"
            alert.runModal()
            return
        }

        let daemonDst = "/Library/Application Support/TBControl/tbcontrold"
        let kextDst = "/Library/Application Support/TBControl/DisableTurboBoost.kext"
        let logPath = "/var/log/tbcontrol.log"

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.tbcontrol.tbcontrold</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(daemonDst)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>UserName</key>
            <string>root</string>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """

        let tempPlistPath = "/tmp/com.tbcontrol.tbcontrold.plist"
        try? plistContent.write(toFile: tempPlistPath, atomically: true, encoding: .utf8)

        let script = """
        do shell script "mkdir -p '/Library/Application Support/TBControl' && cp '\(daemonPath)' '\(daemonDst)' && chown root:wheel '\(daemonDst)' && chmod 755 '\(daemonDst)' && cp -R '\(kextPath)' '\(kextDst)' && chown -R root:wheel '\(kextDst)' && chmod -R 755 '\(kextDst)' && touch '\(logPath)' && chmod 644 '\(logPath)' && chown root:wheel '\(logPath)' && cp '\(tempPlistPath)' /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist && chown root:wheel /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist && launchctl unload /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist 2>/dev/null || true && launchctl load -Fw /Library/LaunchDaemons/com.tbcontrol.tbcontrold.plist" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }

        if let err = error {
            let alert = NSAlert()
            alert.messageText = "安装失败"
            let errorMsg = err[NSAppleScript.errorBriefMessage] as? String ?? "未知错误"
            alert.informativeText = "安装守护进程时出错: \(errorMsg)"
            alert.runModal()
        } else {
            // Refresh immediately to show "Running" state
            self.refresh()
            
            let alert = NSAlert()
            alert.messageText = "安装成功"
            alert.informativeText = "守护进程已成功安装并启动。"
            alert.runModal()
            
            // Secondary refresh after a short delay to allow socket to open
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refresh()
            }
        }
    }

    @objc private func quitApp() {
        // Re-enable Turbo Boost on exit for safety
        _ = ipcClient.sendCommand(["cmd": "set_tb", "enabled": true])
        NSApplication.shared.terminate(nil)
    }
}

extension NSTouchBar {
    @available(macOS 10.12.2, *)
    static func presentSystemModalFunctionBar(_ touchBar: NSTouchBar, placement: Int, systemTrayItemIdentifier: NSTouchBarItem.Identifier) {
        // Support both old and new private API names
        let selectorNames = [
            "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
            "presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:"
        ]
        
        for name in selectorNames {
            let selector = NSSelectorFromString(name)
            if self.responds(to: selector) {
                typealias MethodType = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
                if let impl = self.method(for: selector) {
                    let method = unsafeBitCast(impl, to: MethodType.self)
                    method(self, selector, touchBar, placement, systemTrayItemIdentifier.rawValue as NSString)
                    return
                }
            }
        }
    }
    
    @available(macOS 10.12.2, *)
    static func dismissSystemModalFunctionBar(_ touchBar: NSTouchBar) {
        let selectorNames = [
            "dismissSystemModalTouchBar:",
            "dismissSystemModalFunctionBar:"
        ]
        
        for name in selectorNames {
            let selector = NSSelectorFromString(name)
            if self.responds(to: selector) {
                self.perform(selector, with: touchBar)
                return
            }
        }
    }
}

extension NSTouchBarItem {
    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        if self.responds(to: selector) {
            self.perform(selector, with: item)
        }
    }
    
    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        if self.responds(to: selector) {
            self.perform(selector, with: item)
        }
    }
}
