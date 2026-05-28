import SwiftUI

struct MainWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        TabView {
            DashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge")
                }

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
}

class MainWindowViewModel: ObservableObject {
    @Published var cpuTemp: String = "—"
    @Published var fanSpeed: String = "—"
    @Published var cpuLoad: String = "—"
    @Published var isTurboBoostEnabled: Bool = true
    @Published var currentMode: String = "—"
    @Published var isDaemonRunning: Bool = false

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
            
            switch status.mode {
            case "auto_temp": self.currentMode = "Auto (Temperature)"
            case "auto_battery": self.currentMode = "Auto (Battery)"
            case "auto_load": self.currentMode = "Auto (Load)"
            case "auto_fan": self.currentMode = "Auto (Fan)"
            case "manual": self.currentMode = "Manual"
            default: self.currentMode = "Unknown"
            }
        }
    }
    
    func toggleTurboBoost() {
        let newState = !isTurboBoostEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.ipcClient.setTurboBoost(enabled: newState) ?? false
            if success {
                DispatchQueue.main.async {
                    self?.isTurboBoostEnabled = newState
                }
            }
        }
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

    var body: some View {
        VStack(spacing: 20) {
            Text("System Dashboard")
                .font(.largeTitle)
                .fontWeight(.bold)

            if !viewModel.isDaemonRunning {
                Text("⚠️ Daemon is not running or not installed.")
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            HStack(spacing: 40) {
                StatCard(title: "CPU Temp", value: viewModel.cpuTemp, icon: "thermometer", color: .orange)
                StatCard(title: "Fan Speed", value: viewModel.fanSpeed, icon: "fanblades", color: Color(NSColor.systemTeal))
                StatCard(title: "CPU Load", value: viewModel.cpuLoad, icon: "cpu", color: .purple)
            }
            .padding(.top, 20)

            Divider()

            VStack(spacing: 10) {
                HStack {
                    Text("Turbo Boost Status:")
                        .font(.headline)
                    Text(viewModel.isTurboBoostEnabled ? "Enabled (🔥)" : "Disabled (🧊)")
                        .foregroundColor(viewModel.isTurboBoostEnabled ? .red : .blue)
                        .fontWeight(.bold)
                }

                Button(action: {
                    viewModel.toggleTurboBoost()
                }) {
                    Text(viewModel.isTurboBoostEnabled ? "Disable Turbo Boost" : "Enable Turbo Boost")
                        .padding()
                        .frame(maxWidth: 200)
                        .foregroundColor(.white)
                        .background(viewModel.isTurboBoostEnabled ? Color.blue : Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.isDaemonRunning)
                
                Text("Current Mode: \(viewModel.currentMode)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(width: 120, height: 120)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @AppStorage("autoLaunch") private var autoLaunch = false

    var body: some View {
        Form {
            Section(header: Text("General").font(.headline)) {
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
            
            Section(header: Text("Modes").font(.headline)) {
                Text("Use the Menu Bar icon to configure specific auto-mode thresholds for now.")
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
        }
        .padding()
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
        // We will just let the menubar handle it or we can prompt the user.
        // For simplicity in UI, we can use the same NSApp script or tell user to use MenuBar.
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

struct AboutView: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @State private var updateMessage: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 100, height: 100)
            
            Text("TBControl")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version \(version)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("A lightweight utility to control Intel Turbo Boost on macOS.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button("Check for Updates") {
                    checkForUpdates()
                }
                
                Link("Visit GitHub", destination: URL(string: "https://github.com/BestWaveRock/TBControl")!)
            }
            
            if !updateMessage.isEmpty {
                Text(updateMessage)
                    .font(.footnote)
                    .foregroundColor(.blue)
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
            .frame(maxHeight: 150)
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
    
    private func checkForUpdates() {
        updateMessage = "Checking..."
        let url = URL(string: "https://api.github.com/repos/BestWaveRock/TBControl/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    updateMessage = "Error: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    updateMessage = "Failed to parse version."
                    return
                }
                
                let latest = tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if latest.compare(version, options: .numeric) == .orderedDescending {
                    updateMessage = "New version available: v\(latest). Please visit GitHub to download."
                } else {
                    updateMessage = "You are up to date."
                }
            }
        }.resume()
    }
}
