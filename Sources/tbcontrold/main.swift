import Foundation
import IOKit.ps
import OSLog

let logger = OSLog(subsystem: "com.tbcontrol.tbcontrold", category: "Daemon")
let kextIdentifier = "com.tbcontrol.DisableTurboBoost"

func findKextPath() -> String? {
    let candidates = [
        "/Library/Application Support/TBControl/DisableTurboBoost.kext",
        "/Library/PrivilegedHelperTools/DisableTurboBoost.kext",
        Bundle.main.bundlePath + "/Contents/Resources/DisableTurboBoost.kext",
        CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path + "/DisableTurboBoost.kext" },
    ].compactMap { $0 }

    for path in candidates {
        if FileManager.default.fileExists(atPath: path + "/Contents/MacOS/DisableTurboBoost") {
            return path
        }
    }
    return candidates.first
}

guard let kextPath = findKextPath() else {
    os_log("ERROR: Cannot find DisableTurboBoost.kext", log: logger, type: .error)
    exit(1)
}

let kextManager = KextManager(kextPath: kextPath)
let sensorMonitor = SensorMonitor()
let cpuStats = CPUStats()
let autoEngine = AutoModeEngine()

struct Settings: Codable {
    var tbEnabled: Bool = true
    var mode: AutoMode = .autoTemp
    var config: AutoConfig = AutoConfig()
}

let settingsPath = "/Library/Application Support/TBControl/settings.json"

func loadSettings() -> Settings {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
       let settings = try? JSONDecoder().decode(Settings.self, from: data) {
        return settings
    }
    return Settings()
}

func saveSettings() {
    let settings = Settings(tbEnabled: currentTBState, mode: autoEngine.mode, config: autoEngine.config)
    let url = URL(fileURLWithPath: settingsPath)
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    
    if let data = try? JSONEncoder().encode(settings) {
        try? data.write(to: url, options: .atomic)
    }
}

var _currentTBState = true
let tbStateLock = NSLock()
var currentTBState: Bool {
    get {
        tbStateLock.lock()
        defer { tbStateLock.unlock() }
        return _currentTBState
    }
    set {
        tbStateLock.lock()
        _currentTBState = newValue
        tbStateLock.unlock()
        saveSettings()
    }
}

// Initialize from settings
let initialSettings = loadSettings()
os_log("DEBUG: Loaded settings: mode=%{public}@, tbEnabled=%d", log: logger, type: .debug, initialSettings.mode.rawValue, initialSettings.tbEnabled)
_currentTBState = initialSettings.tbEnabled
autoEngine.mode = initialSettings.mode
autoEngine.config = initialSettings.config

// Sync kext state on startup
if !_currentTBState {
    os_log("DEBUG: Synchronizing kext state: Loading kext because TB is disabled in settings", log: logger, type: .debug)
    _ = kextManager.load()
} else {
    if kextManager.isLoaded {
        os_log("DEBUG: Synchronizing kext state: Unloading kext because TB is enabled in settings", log: logger, type: .debug)
        _ = kextManager.unload()
    }
}

// Global cache for status updates to avoid blocking IPC with slow SMC reads
struct GlobalStatus {
    var sensors: SensorData?
    var load: Double = 0
    var battery: Int = -1
    var kextLoaded: Bool = false
    var lastUpdate: Date = Date.distantPast
}
var cachedStatus = GlobalStatus()
let statusLock = NSLock()

let ipc = DaemonIPC { request, fd in
    handleRequest(request)
}

func handleRequest(_ json: String) -> String? {
    guard let req = try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any],
          let cmd = req["cmd"] as? String else {
        return errorResponse("invalid command")
    }

    switch cmd {
    case "status":
        return statusResponse()

    case "set_tb":
        guard let enabled = req["enabled"] as? Bool else {
            return errorResponse("missing 'enabled' field")
        }
        let success: Bool
        if enabled {
            success = kextManager.unload()
        } else {
            success = kextManager.load()
        }
        
        if success {
            currentTBState = enabled
            return jsonResponse(["success": true, "tb_enabled": currentTBState])
        } else {
            var error = "Kext operation failed. Please ensure the kext is allowed in System Settings > Privacy & Security."
            if !kextManager.checkSIP() {
                error += " (Note: SIP is enabled. You may need to disable SIP or kext-signing to load this unsigned kext on modern macOS.)"
            }
            return jsonResponse([
                "success": false,
                "error": error,
                "tb_enabled": currentTBState
            ])
        }

    case "set_mode":
        guard let modeStr = req["mode"] as? String,
              let mode = AutoMode(rawValue: modeStr) else {
            os_log("DEBUG: Invalid mode requested: %{public}@", log: logger, type: .error, String(describing: req["mode"]))
            return errorResponse("invalid mode")
        }
        os_log("DEBUG: Setting mode to %{public}@", log: logger, type: .debug, mode.rawValue)
        autoEngine.mode = mode
        if let configData = req["config"] as? [String: Any] {
            var newConfig = autoEngine.config
            if let temp = configData["temp_threshold"] as? Double {
                newConfig.tempThreshold = temp
            }
            if let hys = configData["temp_hysteresis"] as? Double {
                newConfig.tempHysteresis = hys
            }
            if let batt = configData["battery_threshold"] as? Int {
                newConfig.batteryThreshold = batt
            }
            if let fan = configData["fan_threshold"] as? Int {
                newConfig.fanThreshold = fan
            }
            autoEngine.config = newConfig
        }
        saveSettings()
        return jsonResponse(["success": true, "mode": mode.rawValue])

    case "set_fan_speed":
        guard let fanId = req["id"] as? Int,
              let rpm = req["rpm"] as? Int else {
            return errorResponse("missing 'id' or 'rpm' field")
        }
        let success = sensorMonitor.setFanSpeed(id: fanId, rpm: rpm)
        return jsonResponse(["success": success])

    case "reset_fans":
        let success = sensorMonitor.resetFanControl()
        return jsonResponse(["success": success])

    case "quit":
        DispatchQueue.main.async {
            exit(0)
        }
        return jsonResponse(["success": true])

    default:
        return errorResponse("unknown command: \(cmd)")
    }
}

func statusResponse() -> String {
    statusLock.lock()
    let status = cachedStatus
    statusLock.unlock()

    var response: [String: Any] = [
        "success": true,
        "tb_enabled": currentTBState,
        "cpu_load": status.load,
        "mode": autoEngine.mode.rawValue,
        "kext_loaded": status.kextLoaded,
        "battery_level": status.battery,
        "is_daemon": true
    ]

    if let temp = status.sensors?.cpuTemp {
        response["cpu_temp"] = temp
    }
    if let fans = status.sensors?.fanSpeeds {
        response["fan_speeds"] = fans
        if !fans.isEmpty {
            response["fan_speed"] = fans.max() ?? 0
        }
    }

    return jsonResponse(response)
}

func currentBatteryStatus() -> (level: Int, isPluggedIn: Bool) {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty,
              let desc = IOPSGetPowerSourceDescription(blob, list[0])?.takeUnretainedValue() as? [String: Any] else {
        return (-1, true)
    }
    
    let level = desc[kIOPSCurrentCapacityKey as String] as? Int ?? -1
    let powerSource = desc[kIOPSPowerSourceStateKey as String] as? String
    let isPluggedIn = powerSource == kIOPSACPowerValue as String
    
    return (level, isPluggedIn)
}

func jsonResponse(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
}

func errorResponse(_ msg: String) -> String {
    return jsonResponse(["success": false, "error": msg])
}

func setupSignalHandlers() {
    let signals = [SIGINT, SIGTERM, SIGHUP]
    for sig in signals {
        signal(sig) { s in
            os_log("DEBUG: Received signal %d, cleaning up...", log: logger, type: .info, s)
            // Re-enable Turbo Boost for safety
            // Note: In a signal handler, we should be careful with what we call.
            exit(0)
        }
    }
}

signal(SIGPIPE, SIG_IGN)
setupSignalHandlers()

guard ipc.start() else {
    os_log("ERROR: Failed to start IPC server", log: logger, type: .error)
    exit(1)
}

os_log("TBControl daemon started", log: logger, type: .info)
autoEngine.onAction = { shouldEnable in
    if shouldEnable {
        _ = kextManager.unload()
    } else {
        _ = kextManager.load()
    }
    currentTBState = shouldEnable
}

Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    let sensors = sensorMonitor.readSensors()
    let load = cpuStats.getLoad()
    let battInfo = currentBatteryStatus()
    let loaded = kextManager.isLoaded

    statusLock.lock()
    cachedStatus.sensors = sensors
    cachedStatus.load = load
    cachedStatus.battery = battInfo.level
    cachedStatus.kextLoaded = loaded
    cachedStatus.lastUpdate = Date()
    statusLock.unlock()

    if let t = sensors?.cpuTemp, t > 0 {
        let fanStr = sensors?.fanSpeeds?.map { "\($0)" }.joined(separator: "/") ?? "0"
        os_log("DEBUG: Current Temp: %.1f°C, Fan: %{public}@ rpm, Load: %.1f%%, Plugged: %d", log: logger, type: .debug, t, fanStr, load, battInfo.isPluggedIn ? 1 : 0)
    }

    guard autoEngine.mode != .manual else { return }

    if let action = autoEngine.evaluate(cpuTemp: sensors?.cpuTemp ?? 0, 
                                         cpuLoad: load,
                                         fanSpeed: sensors?.fanSpeeds?.max() ?? 0,
                                         batteryLevel: battInfo.level >= 0 ? battInfo.level : nil,
                                         isPluggedIn: battInfo.isPluggedIn,
                                         runningApps: []) {
        autoEngine.onAction?(action)
    }
}

RunLoop.main.run()
