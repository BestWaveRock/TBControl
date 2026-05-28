import SwiftUI

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct MainWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            TabView {
                DashboardView(viewModel: viewModel)
                    .tabItem {
                        Label("Dashboard", systemImage: "gauge")
                    }

                SettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    
                TouchBarConfigView(viewModel: viewModel)
                    .tabItem {
                        Label("Touch Bar", systemImage: "macbook.and.ipad")
                    }

                AboutView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .padding()
        }
        .frame(minWidth: 550, minHeight: 450)
    }
}

class MainWindowViewModel: ObservableObject {
    @Published var cpuTemp: String = "—"
    @Published var fanSpeed: String = "—"
    @Published var cpuLoad: String = "—"
    @Published var wattage: String = "—"
    @Published var netSpeed: String = "—"
    @Published var memoryUsage: String = "—"
    @Published var isTurboBoostEnabled: Bool = true
    @Published var currentMode: String = "manual"
    @Published var isDaemonRunning: Bool = false
    @Published var isTouchBarEnabled: Bool = UserDefaults.standard.bool(forKey: "isTouchBarEnabled")
    @Published var touchBarItems: [String] = UserDefaults.standard.stringArray(forKey: "touchBarItems") ?? ["tbState", "mode", "temp", "fan", "load", "battery", "freq", "memory", "wattage", "network", "refresh"]
    @Published var batteryThreshold: Int = 30

    private let ipcClient = IPCClient()
    private var timer: Timer?

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        timer?.fire()
    }

    func refreshStatus() {
        let daemonStatus = checkDaemonRunning()
        
        DispatchQueue.main.async {
            self.isDaemonRunning = daemonStatus
        }

        guard let status = ipcClient.getStatus() else { return }

        DispatchQueue.main.async {
            self.isTurboBoostEnabled = status.tbEnabled
            self.cpuTemp = status.cpuTemp != nil ? String(format: "%.1f°C", status.cpuTemp!) : "—"
            
            if let fans = status.fanSpeeds, !fans.isEmpty {
                self.fanSpeed = fans.map { "\($0)" }.joined(separator: " / ") + " rpm"
            } else {
                self.fanSpeed = "—"
            }
            
            self.cpuLoad = String(format: "%.1f%%", status.cpuLoad)
            self.wattage = String(format: "%.1fW", status.wattage)
            self.memoryUsage = "Estimated" // Memory calculation is in TouchBarController currently, could be moved
            
            func formatNet(_ bytesPerSec: Double) -> String {
                if bytesPerSec >= 1024 * 1024 {
                    return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
                } else if bytesPerSec >= 1024 {
                    return String(format: "%.1f KB/s", bytesPerSec / 1024)
                } else {
                    return String(format: "%.0f B/s", bytesPerSec)
                }
            }
            self.netSpeed = "↓\(formatNet(status.netIn)) ↑\(formatNet(status.netOut))"
            
            self.currentMode = status.mode
            self.isTouchBarEnabled = UserDefaults.standard.bool(forKey: "isTouchBarEnabled")
            self.touchBarItems = UserDefaults.standard.stringArray(forKey: "touchBarItems") ?? ["tbState", "mode", "temp", "fan", "load", "battery", "freq", "memory", "wattage", "network", "refresh"]
        }
    }
    
    func toggleTurboBoost() {
        let newState = !isTurboBoostEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.ipcClient.setTurboBoost(enabled: newState) ?? false
            if success {
                self?.refreshStatus()
            }
        }
    }
    
    func setMode(_ mode: String, config: [String: Any] = [:]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.ipcClient.setMode(mode, config: config) ?? false
            if success {
                self?.refreshStatus()
            }
        }
    }
    
    func saveTouchBarConfig() {
        UserDefaults.standard.set(isTouchBarEnabled, forKey: "isTouchBarEnabled")
        UserDefaults.standard.set(touchBarItems, forKey: "touchBarItems")
        NotificationCenter.default.post(name: NSNotification.Name("TouchBarConfigChanged"), object: nil)
    }

    private func checkDaemonRunning() -> Bool {
        if FileManager.default.fileExists(atPath: "/tmp/tbcontrol.sock") {
            return true
        }
        return false
    }
}

struct DashboardView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    
    var modeDisplayName: String {
        switch viewModel.currentMode {
        case "auto_temp": return "Auto (Temperature)"
        case "auto_battery": return "Auto (Battery)"
        case "auto_load": return "Auto (Load)"
        case "auto_fan": return "Auto (Fan)"
        case "manual": return "Manual"
        default: return "Unknown"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("System Dashboard")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))

                if !viewModel.isDaemonRunning {
                    Text("⚠️ Daemon is not running or not installed.")
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 20) {
                    StatCard(title: "CPU Temp", value: viewModel.cpuTemp, icon: "thermometer", color: .orange)
                    StatCard(title: "Fan Speed", value: viewModel.fanSpeed, icon: "fanblades", color: Color(NSColor.systemTeal))
                    StatCard(title: "CPU Load", value: viewModel.cpuLoad, icon: "cpu", color: .purple)
                    StatCard(title: "Power", value: viewModel.wattage, icon: "bolt.fill", color: .yellow)
                    StatCard(title: "Network", value: viewModel.netSpeed, icon: "network", color: .blue)
                }
                .padding(.top, 10)

                Divider()

                VStack(spacing: 15) {
                    HStack {
                        Text("Turbo Boost:")
                            .font(.system(.headline, design: .monospaced))
                        Text(viewModel.isTurboBoostEnabled ? "Enabled (🔥)" : "Disabled (🧊)")
                            .foregroundColor(viewModel.isTurboBoostEnabled ? .red : .blue)
                            .fontWeight(.bold)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button(action: {
                        viewModel.toggleTurboBoost()
                    }) {
                        Text(viewModel.isTurboBoostEnabled ? "Disable Turbo Boost" : "Enable Turbo Boost")
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .foregroundColor(.white)
                            .background(viewModel.isTurboBoostEnabled ? Color.blue : Color.red)
                            .cornerRadius(8)
                            .font(.system(.body, design: .monospaced))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!viewModel.isDaemonRunning)
                    
                    Text("Current Mode: \(modeDisplayName)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
            }
            .padding()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @AppStorage("autoLaunch") private var autoLaunch = false

    var body: some View {
        Form {
            Section(header: Text("General").font(.system(.headline, design: .monospaced))) {
                Toggle("Launch at Login", isOn: $autoLaunch)
                    .onChange(of: autoLaunch) { newValue in
                        toggleAutoLaunch(enabled: newValue)
                    }
                
                Button("Install Daemon") {
                    installDaemon()
                }
                .disabled(viewModel.isDaemonRunning)
                
                Button("Uninstall Daemon") {
                    uninstallDaemon()
                }
                .disabled(!viewModel.isDaemonRunning)
            }
            
            Section(header: Text("Modes").font(.system(.headline, design: .monospaced))) {
                Picker("Current Mode", selection: $viewModel.currentMode) {
                    Text("Manual").tag("manual")
                    Text("Auto (Temperature)").tag("auto_temp")
                    Text("Auto (Battery)").tag("auto_battery")
                    Text("Auto (Load)").tag("auto_load")
                    Text("Auto (Fan)").tag("auto_fan")
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: viewModel.currentMode) { newValue in
                    viewModel.setMode(newValue)
                }
                
                if viewModel.currentMode == "auto_battery" {
                    Picker("Battery Threshold", selection: $viewModel.batteryThreshold) {
                        Text("10%").tag(10)
                        Text("20%").tag(20)
                        Text("30%").tag(30)
                        Text("40%").tag(40)
                        Text("50%").tag(50)
                    }
                    .onChange(of: viewModel.batteryThreshold) { newValue in
                        viewModel.setMode("auto_battery", config: ["battery_threshold": newValue])
                    }
                }
            }
        }
        .padding()
        .onAppear {
            syncAutoLaunchState()
        }
    }
    
    private func syncAutoLaunchState() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"System Events\" to get name of every login item"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        autoLaunch = output.contains("TBControl")
    }
    
    private func toggleAutoLaunch(enabled: Bool) {
        let appPath = Bundle.main.bundlePath
        let script: String
        if !enabled {
            script = "tell application \"System Events\" to delete login item \"TBControl\""
        } else {
            script = "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", name:\"TBControl\", hidden:false}"
        }
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
    
    private func installDaemon() {
        let alert = NSAlert()
        alert.messageText = "Install Daemon"
        alert.informativeText = "Please use the Menu Bar icon -> 'Install Daemon' option for administrator privileges."
        alert.runModal()
    }
    
    private func uninstallDaemon() {
         let alert = NSAlert()
         alert.messageText = "Uninstall Components"
         alert.informativeText = "Please use the Menu Bar icon -> 'Uninstall Components' to completely remove the daemon."
         alert.runModal()
    }
}

struct TouchBarConfigView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    let allAvailableItems = [
        "tbState": "TB Status (🔥/🧊)",
        "mode": "Operation Mode (🎯)",
        "temp": "CPU Temp (🌡)",
        "fan": "Fan Speed (🌀)",
        "load": "CPU Load (⚡️)",
        "battery": "Battery (🔋)",
        "freq": "Frequency (🚀)",
        "memory": "Memory (🧠)",
        "wattage": "Power (🔌)",
        "network": "Network (🌐)",
        "refresh": "Refresh Rate (⏱)"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Touch Bar Configuration")
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
            
            Toggle("Enable Touch Bar System-Wide", isOn: $viewModel.isTouchBarEnabled)
                .font(.system(.body, design: .monospaced))
                .onChange(of: viewModel.isTouchBarEnabled) { _ in
                    viewModel.saveTouchBarConfig()
                }

            Text("Select items to display on Touch Bar:")
                .foregroundColor(.secondary)
                .font(.system(.subheadline, design: .monospaced))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allAvailableItems.keys.sorted(), id: \.self) { key in
                        Toggle(allAvailableItems[key] ?? key, isOn: Binding(
                            get: { viewModel.touchBarItems.contains(key) },
                            set: { isEnabled in
                                if isEnabled {
                                    if !viewModel.touchBarItems.contains(key) {
                                        viewModel.touchBarItems.append(key)
                                    }
                                } else {
                                    viewModel.touchBarItems.removeAll { $0 == key }
                                }
                                viewModel.saveTouchBarConfig()
                            }
                        ))
                        .padding(.vertical, 2)
                    }
                }
                .padding(.trailing, 10)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct AboutView: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 5) {
                Text("TBControl")
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                
                Text("Version \(version)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text("A lightweight utility to control Intel Turbo Boost on macOS.")
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button(action: {
                    UpdateManager.shared.checkForUpdates(force: true)
                }) {
                    HStack {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        }
                        Text("Check for Updates")
                    }
                }
                .disabled(isChecking)
                
                Link("Visit GitHub", destination: URL(string: "https://github.com/BestWaveRock/TBControl")!)
            }
            
            Divider()
            
            ScrollView {
                Text("""
                MIT License
                
                Copyright (c) 2026 BestWaveRock
                
                Permission is hereby granted, free of charge, to any person obtaining a copy
                of this software and associated documentation files (the "Software"), to deal
                in the Software without restriction, including without limitation the rights
                to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
                copies of the Software, and to permit persons to whom the Software is
                furnished to do so, subject to the following conditions:
                
                The above copyright notice and this permission notice shall be included in all
                copies or substantial portions of the Software.
                
                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
                SOFTWARE.
                """)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding()
            .background(VisualEffectBlur(material: .popover, blendingMode: .withinWindow))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}
