import Foundation
import IOKit.ps
import OSLog

let logger = OSLog(subsystem: "com.tbcontrol.tbcontrold", category: "Daemon")
let kextIdentifier = "com.tbcontrol.DisableTurboBoost"

func findKextPath() -> String? {
    let possiblePaths = [
        "/Library/Application Support/TBControl/DisableTurboBoost.kext",
        Bundle.main.bundlePath + "/DisableTurboBoost.kext",
        Bundle.main.bundlePath + "/Contents/Resources/DisableTurboBoost.kext",
        "./Kext/build/DisableTurboBoost.kext"
    ]
    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return nil
}

let kextManager = KextManager(kextPath: findKextPath() ?? "")
let sensorMonitor = SensorMonitor()
let cpuStats = CPUStats()
let autoEngine = AutoModeEngine()

var currentTBState: Bool = true {
    didSet {
        if currentTBState {
            _ = kextManager.unload()
        } else {
            _ = kextManager.load()
        }
    }
}

// Global cache for status updates to avoid blocking IPC with slow SMC reads
struct GlobalStatus {
    var sensors: SensorData?
    var load: Double = 0
    var battery: Int = -1
    var isCharging: Bool = false
    var kextLoaded: Bool = false
    var lastUpdate: Date = Date.distantPast
    var wattage: Double?
    var cpuFrequency: Double?
    var netIn: UInt64 = 0
    var netOut: UInt64 = 0
    var netInSpeed: Double = 0
    var netOutSpeed: Double = 0
    var lastNetUpdate: Date = Date()
}
var cachedStatus = GlobalStatus()
let statusLock = NSLock()

var refreshInterval: TimeInterval = 3.0
var refreshTimer: Timer?

func setupRefreshTimer(interval: TimeInterval) {
    refreshTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
        refreshStatus()
    }
}

func getNetworkBytes() -> (in: UInt64, out: UInt64) {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var len = 0
    if sysctl(&mib, 6, nil, &len, nil, 0) < 0 { return (0, 0) }
    var buf = [Int8](repeating: 0, count: len)
    if sysctl(&mib, 6, &buf, &len, nil, 0) < 0 { return (0, 0) }
    
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0
    var offset = 0
    while offset < len {
        let hdr = buf.withUnsafeBufferPointer { ptr -> if_msghdr in
            return ptr.baseAddress!.advanced(by: offset).withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
        }
        if hdr.ifm_type == RTM_IFINFO2 {
            let if2 = buf.withUnsafeBufferPointer { ptr -> if_msghdr2 in
                return ptr.baseAddress!.advanced(by: offset).withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
            }
            if if2.ifm_data.ifi_type == 6 || if2.ifm_data.ifi_type == 71 {
                totalIn += if2.ifm_data.ifi_ibytes
                totalOut += if2.ifm_data.ifi_obytes
            }
        }
        offset += Int(hdr.ifm_msglen)
    }
    return (totalIn, totalOut)
}

func refreshStatus() {
    let sensors = sensorMonitor.readSensors()
    let load = cpuStats.getLoad()
    let battInfo = currentBatteryStatus()
    let loaded = kextManager.isLoaded
    let wattage = sensorMonitor.readWattage()
    let cpuFreq = sensorMonitor.readCPUFrequency()
    let net = getNetworkBytes()
    let now = Date()

    statusLock.lock()
    let duration = now.timeIntervalSince(cachedStatus.lastNetUpdate)
    if duration > 0 {
        cachedStatus.netInSpeed = Double(net.in > cachedStatus.netIn ? net.in - cachedStatus.netIn : 0) / duration
        cachedStatus.netOutSpeed = Double(net.out > cachedStatus.netOut ? net.out - cachedStatus.netOut : 0) / duration
    }
    cachedStatus.netIn = net.in
    cachedStatus.netOut = net.out
    cachedStatus.lastNetUpdate = now
    
    cachedStatus.sensors = sensors
    cachedStatus.load = load
    cachedStatus.battery = battInfo.level
    cachedStatus.isCharging = battInfo.isPluggedIn
    cachedStatus.kextLoaded = loaded
    cachedStatus.wattage = wattage
    cachedStatus.cpuFrequency = cpuFreq
    cachedStatus.lastUpdate = now
    statusLock.unlock()

    if let t = sensors?.cpuTemp, t > 0 {
        let fanStr = sensors?.fanSpeeds?.map { "\($0)" }.joined(separator: "/") ?? "0"
        os_log("DEBUG: Current Temp: %.1f°C, Fan: %{public}@ rpm, Load: %.1f%%, Watt: %.1fW", log: logger, type: .debug, t, fanStr, load, wattage ?? 0)
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

    case "set_refresh":
        guard let interval = req["interval"] as? Double else {
            return errorResponse("missing 'interval'")
        }
        refreshInterval = interval
        setupRefreshTimer(interval: interval)
        return jsonResponse(["success": true])

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
            if let batteryThreshold = configData["battery_threshold"] as? Int {
                var config = autoEngine.config
                config.batteryThreshold = batteryThreshold
                autoEngine.config = config
            }
        }
        return jsonResponse(["success": true])

    case "set_fan_speed":
        guard let id = req["id"] as? Int, let rpm = req["rpm"] as? Int else {
            return errorResponse("missing 'id' or 'rpm'")
        }
        let ok = sensorMonitor.setFanSpeed(id: id, rpm: rpm)
        return jsonResponse(["success": ok])

    case "reset_fans":
        let ok = sensorMonitor.resetFanControl()
        return jsonResponse(["success": ok])

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
        "is_charging": status.isCharging,
        "wattage": status.wattage ?? 0,
        "cpu_freq": status.cpuFrequency ?? 0,
        "net_in": status.netInSpeed,
        "net_out": status.netOutSpeed,
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

setupRefreshTimer(interval: refreshInterval)

RunLoop.main.run()
