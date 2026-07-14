import SwiftUI
import Charts

// MARK: - Window Root

struct MainWindowView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case settings = "Settings"
        case touchbar = "Touch Bar"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.33percent"
            case .settings: return "gearshape.2"
            case .touchbar: return "keyboard.trianglebadge.exclamationmark"
            case .about: return "info.bubble"
            }
        }

        var color: Color {
            switch self {
            case .dashboard: return .cyan
            case .settings: return .indigo
            case .touchbar: return .orange
            case .about: return .secondary
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detailView(for: selectedTab)
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(Tab.allCases, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                Label(tab.rawValue, systemImage: tab.icon)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                    .padding(.vertical, 4)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("TBControl")
                    .font(.system(size: 15, weight: .bold))
            }
        }
    }

    @ViewBuilder
    private func detailView(for tab: Tab) -> some View {
        switch tab {
        case .dashboard: DashboardView(viewModel: viewModel)
        case .settings: SettingsView(viewModel: viewModel)
        case .touchbar: TouchBarConfigView(viewModel: viewModel)
        case .about: AboutView()
        }
    }
}

// MARK: - ViewModel

class MainWindowViewModel: ObservableObject {
    @Published var cpuTemp: String = "—"
    @Published var fanSpeed: String = "—"
    @Published var cpuLoad: String = "—"
    @Published var cpuFrequency: String = "—"
    @Published var wattage: String = "—"
    @Published var netSpeed: String = "—"
    @Published var memoryUsage: String = "—"
    @Published var isTurboBoostEnabled: Bool = true
    @Published var currentMode: String = "manual"
    @Published var isDaemonRunning: Bool = false
    @Published var isTouchBarEnabled: Bool = UserDefaults.standard.bool(forKey: "isTouchBarEnabled")
    @Published var touchBarItems: [String] = UserDefaults.standard.stringArray(forKey: "touchBarItems") ?? ["tbState", "mode", "temp", "fan", "load", "battery", "freq", "memory", "wattage", "network", "refresh"]
    @Published var batteryThreshold: Int = 30

    /// Numeric values for gauges
    @Published var cpuTempValue: Double = 0
    @Published var cpuLoadValue: Double = 0
    @Published var fanSpeedValue: Double = 0
    @Published var wattageValue: Double = 0
    @Published var cpuFreqValue: Double = 0

    /// History buffer for Charts
    @Published var tempHistory: [DataPoint] = []
    @Published var loadHistory: [DataPoint] = []

    private let ipcClient = IPCClient()
    private var timer: Timer?
    private var sampleIndex: Int = 0

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
        DispatchQueue.main.async { self.isDaemonRunning = daemonStatus }
        guard let status = ipcClient.getStatus() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                self.isTurboBoostEnabled = status.tbEnabled
                self.currentMode = status.mode

                // CPU Temp
                if let t = status.cpuTemp {
                    self.cpuTemp = String(format: "%.1f°C", t)
                    self.cpuTempValue = t
                } else {
                    self.cpuTemp = "—"
                    self.cpuTempValue = 0
                }

                // Fan
                if let fans = status.fanSpeeds, !fans.isEmpty {
                    let avg = Double(fans.reduce(0, +)) / Double(fans.count)
                    self.fanSpeed = fans.map { "\($0)" }.joined(separator: " / ") + " rpm"
                    self.fanSpeedValue = avg
                } else {
                    self.fanSpeed = "—"
                    self.fanSpeedValue = 0
                }

                // CPU Load
                self.cpuLoad = String(format: "%.1f%%", status.cpuLoad)
                self.cpuLoadValue = status.cpuLoad

                // Frequency
                self.cpuFreqValue = status.cpuFreq > 0 ? status.cpuFreq : 2.30
                self.cpuFrequency = status.cpuFreq > 0 ? String(format: "%.2f GHz", status.cpuFreq) : "2.30 GHz"

                // Wattage
                self.wattageValue = status.wattage
                self.wattage = String(format: "%.1f W", status.wattage)

                // Network
                func formatNet(_ bps: Double) -> String {
                    if bps >= 1024 * 1024 { return String(format: "%.1f MB/s", bps / (1024 * 1024)) }
                    if bps >= 1024 { return String(format: "%.1f KB/s", bps / 1024) }
                    return String(format: "%.0f B/s", bps)
                }
                self.netSpeed = "↓\(formatNet(status.netIn))  ↑\(formatNet(status.netOut))"

                // History
                self.sampleIndex += 1
                let now = Date()
                self.tempHistory.append(DataPoint(time: now, value: status.cpuTemp ?? 0, label: "Temp"))
                self.loadHistory.append(DataPoint(time: now, value: status.cpuLoad, label: "Load"))
                if self.tempHistory.count > 60 { self.tempHistory.removeFirst() }
                if self.loadHistory.count > 60 { self.loadHistory.removeFirst() }
            }
        }
    }

    func toggleTurboBoost() {
        let newState = !isTurboBoostEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let success = self.ipcClient.setTurboBoost(enabled: newState)
            if success {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        self.isTurboBoostEnabled = newState
                    }
                }
            }
        }
    }

    func setMode(_ mode: String, config: [String: Any] = [:]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.ipcClient.setMode(mode, config: config)
        }
    }

    func saveTouchBarConfig() {
        UserDefaults.standard.set(isTouchBarEnabled, forKey: "isTouchBarEnabled")
        UserDefaults.standard.set(touchBarItems, forKey: "touchBarItems")
        NotificationCenter.default.post(name: NSNotification.Name("TouchBarConfigChanged"), object: nil)
    }

    private func checkDaemonRunning() -> Bool {
        FileManager.default.fileExists(atPath: "/tmp/tbcontrol.sock")
    }

    func modeDisplayName(_ mode: String) -> String {
        switch mode {
        case "auto_temp": return "Temperature"
        case "auto_battery": return "Battery"
        case "auto_load": return "Load"
        case "auto_fan": return "Fan"
        case "manual": return "Manual"
        default: return "Unknown"
        }
    }
}

// MARK: - Data Models

struct DataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
    let label: String
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                header

                if !viewModel.isDaemonRunning {
                    daemonOfflineBanner
                }

                // Gauge Row
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    GaugeCard(
                        title: "CPU Temperature",
                        value: viewModel.cpuTempValue,
                        unit: "°C",
                        range: 0...120,
                        gradient: Gradient(colors: [.cyan, .mint, .yellow, .red]),
                        icon: "thermometer.medium",
                        symbol: viewModel.cpuTemp
                    )
                    GaugeCard(
                        title: "CPU Load",
                        value: viewModel.cpuLoadValue,
                        unit: "%",
                        range: 0...100,
                        gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                        icon: "cpu",
                        symbol: viewModel.cpuLoad
                    )
                    GaugeCard(
                        title: "Fan Speed",
                        value: viewModel.fanSpeedValue,
                        unit: " rpm",
                        range: 0...7000,
                        gradient: Gradient(colors: [.teal, .blue, .indigo]),
                        icon: "fanblades.fill",
                        symbol: viewModel.fanSpeed
                    )
                    GaugeCard(
                        title: "Power Draw",
                        value: viewModel.wattageValue,
                        unit: "W",
                        range: 0...120,
                        gradient: Gradient(colors: [.yellow, .orange, .red]),
                        icon: "bolt.fill",
                        symbol: viewModel.wattage
                    )
                }
                .padding(.horizontal)

                // Freq + Network Row
                gridRow

                // Charts
                chartsSection
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(.background.opacity(0.3))
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Monitor")
                    .font(.system(size: 26, weight: .bold))
                Text(viewModel.modeDisplayName(viewModel.currentMode) + " Mode" + " · " + viewModel.cpuFrequency)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            TBBadge(isEnabled: viewModel.isTurboBoostEnabled)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Daemon Warning

    private var daemonOfflineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Text("Daemon is not running. Some features require the background service.")
                .font(.callout)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.red.opacity(0.25), lineWidth: 1))
    }

    // MARK: Grid Row

    private var gridRow: some View {
        HStack(spacing: 16) {
            MetricBox(
                title: "Frequency",
                value: viewModel.cpuFrequency,
                icon: "speedometer",
                color: .indigo,
                subtitle: "Current Clock"
            )
            MetricBox(
                title: "Network",
                value: viewModel.netSpeed,
                icon: "network",
                color: .blue,
                subtitle: "Download · Upload"
            )
        }
    }

    // MARK: Charts

    private var chartsSection: some View {
        VStack(spacing: 16) {
            ChartCard(
                title: "CPU Temperature",
                data: viewModel.tempHistory,
                color: .orange,
                gradient: Gradient(colors: [.orange.opacity(0.3), .clear]),
                domain: 0...120
            )
            ChartCard(
                title: "CPU Load",
                data: viewModel.loadHistory,
                color: .purple,
                gradient: Gradient(colors: [.purple.opacity(0.3), .clear]),
                domain: 0...100
            )
        }
    }
}

// MARK: - Gauge Card

struct GaugeCard: View {
    let title: String
    let value: Double
    let unit: String
    let range: ClosedRange<Double>
    let gradient: Gradient
    let icon: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.multicolor)

            Gauge(value: value, in: range) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } currentValueLabel: {
                Text(symbol)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(gradient)
            .scaleEffect(1.05)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Metric Box

struct MetricBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
    }
}

// MARK: - Chart Card

struct ChartCard: View {
    let title: String
    let data: [DataPoint]
    let color: Color
    let gradient: Gradient
    let domain: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Chart {
                ForEach(data) { pt in
                    LineMark(
                        x: .value("Time", pt.time),
                        y: .value(title, pt.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.3), radius: 3, y: 2)

                    AreaMark(
                        x: .value("Time", pt.time),
                        y: .value(title, pt.value)
                    )
                    .foregroundStyle(gradient)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic) { val in
                    AxisValueLabel()
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 100)
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
    }
}

// MARK: - TB Badge

struct TBBadge: View {
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isEnabled ? Color.red : Color.blue)
                .frame(width: 8, height: 8)
            Text(isEnabled ? "Turbo Boost ON" : "Turbo Boost OFF")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isEnabled ? Color.red.opacity(0.12) : Color.blue.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isEnabled ? Color.red.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var viewModel: MainWindowViewModel
    @AppStorage("autoLaunch") private var autoLaunch = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoLaunch) {
                    Label("Launch at Login", systemImage: "power")
                }
                .onChange(of: autoLaunch) { _, newValue in toggleAutoLaunch(enabled: newValue) }

                Button {
                    installDaemon()
                } label: {
                    Label("Install Daemon", systemImage: "arrow.down.circle.dotted")
                }
                .disabled(viewModel.isDaemonRunning)

                Button {
                    uninstallDaemon()
                } label: {
                    Label("Uninstall Daemon", systemImage: "trash")
                }
                .disabled(!viewModel.isDaemonRunning)
            } header: {
                Label("General", systemImage: "gearshape")
            }

            Section {
                Picker(selection: $viewModel.currentMode) {
                    ForEach([
                        ("manual", "Manual"),
                        ("auto_temp", "Auto — Temperature"),
                        ("auto_battery", "Auto — Battery"),
                        ("auto_load", "Auto — CPU Load"),
                        ("auto_fan", "Auto — Fan Speed"),
                    ], id: \.0) { (tag, label) in
                        Text(label).tag(tag)
                    }
                } label: {
                    Label("Operation Mode", systemImage: "arrow.triangle.branch")
                }
                .onChange(of: viewModel.currentMode) { _, newValue in viewModel.setMode(newValue) }

                if viewModel.currentMode == "auto_battery" {
                    Picker("Battery Threshold", selection: $viewModel.batteryThreshold) {
                        ForEach([10, 20, 30, 40, 50], id: \.self) { pct in
                            Text("\(pct)%").tag(pct)
                        }
                    }
                    .onChange(of: viewModel.batteryThreshold) { _, newValue in
                        viewModel.setMode("auto_battery", config: ["battery_threshold": newValue])
                    }
                }
            } header: {
                Label("Modes", systemImage: "list.bullet.circle")
            }

            Section {
                HStack {
                    Label("Turbo Boost", systemImage: "bolt.circle.fill")
                    Spacer()
                    Toggle("", isOn: $viewModel.isTurboBoostEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: viewModel.isTurboBoostEnabled) { _, _ in
                            viewModel.toggleTurboBoost()
                        }
                }
            } header: {
                Label("Controls", systemImage: "switch.programmable")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { syncAutoLaunchState() }
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
        let script = enabled
            ? "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", name:\"TBControl\", hidden:false}"
            : "tell application \"System Events\" to delete login item \"TBControl\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func installDaemon() {
        let alert = NSAlert()
        alert.messageText = "Install Daemon"
        alert.informativeText = "Please use the Menu Bar icon → 'Install Daemon' option for administrator privileges."
        alert.runModal()
    }

    private func uninstallDaemon() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Components"
        alert.informativeText = "Please use the Menu Bar icon → 'Uninstall Components' to completely remove the daemon."
        alert.runModal()
    }
}

// MARK: - Touch Bar Config

struct TouchBarConfigView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    let allItems: [(key: String, label: String, icon: String)] = [
        ("tbState", "TB Status", "flame"),
        ("mode", "Operation Mode", "target"),
        ("temp", "CPU Temperature", "thermometer"),
        ("fan", "Fan Speed", "fanblades"),
        ("load", "CPU Load", "cpu"),
        ("battery", "Battery", "battery.100"),
        ("freq", "Frequency", "speedometer"),
        ("memory", "Memory", "memorychip"),
        ("wattage", "Power Draw", "bolt"),
        ("network", "Network", "network"),
        ("refresh", "Refresh Rate", "arrow.clockwise"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Touch Bar Configuration")
                .font(.system(size: 22, weight: .bold))

            Toggle(isOn: $viewModel.isTouchBarEnabled) {
                Label("Enable Touch Bar Dashboard", systemImage: "keyboard.badge.ellipsis")
            }
            .toggleStyle(.switch)
            .onChange(of: viewModel.isTouchBarEnabled) { _, _ in viewModel.saveTouchBarConfig() }

            Divider()

            Text("Display Items")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 8) {
                    ForEach(allItems, id: \.key) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            Text(item.label)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { viewModel.touchBarItems.contains(item.key) },
                                set: { enabled in
                                    if enabled { viewModel.touchBarItems.append(item.key) }
                                    else { viewModel.touchBarItems.removeAll { $0 == item.key } }
                                    viewModel.saveTouchBarConfig()
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - About

struct AboutView: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)

            VStack(spacing: 4) {
                Text("TBControl")
                    .font(.system(size: 28, weight: .bold))
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("A lightweight utility to control Intel Turbo Boost on macOS.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 16) {
                Button {
                    isChecking = true
                    UpdateManager.shared.checkForUpdates(force: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { isChecking = false }
                } label: {
                    Label("Check Updates", systemImage: "arrow.down.circle")
                }
                .disabled(isChecking)

                Link(destination: URL(string: "https://github.com/BestWaveRock/TBControl")!) {
                    Label("GitHub", systemImage: "arrow.up.forward.app")
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("MIT License · © 2026 BestWaveRock")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.2))
    }
}
