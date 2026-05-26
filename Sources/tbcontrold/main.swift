import Foundation
import IOKit.ps

let kextIdentifier = "com.tbcontrol.DisableTurboBoost"

func findKextPath() -> String? {
    let candidates = [
        Bundle.main.bundlePath + "/Contents/Resources/DisableTurboBoost.kext",
        CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path + "/DisableTurboBoost.kext" },
        "/Library/Application Support/TBControl/DisableTurboBoost.kext",
    ].compactMap { $0 }

    for path in candidates {
        if FileManager.default.fileExists(atPath: path + "/Contents/MacOS/DisableTurboBoost") {
            return path
        }
    }
    return candidates.first
}

guard let kextPath = findKextPath() else {
    print("ERROR: Cannot find DisableTurboBoost.kext")
    exit(1)
}

let kextManager = KextManager(kextPath: kextPath)
let sensorMonitor = SensorMonitor()
let cpuStats = CPUStats()
let autoEngine = AutoModeEngine()
var currentTBState = true

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
        if success { currentTBState = enabled }
        return jsonResponse(["success": success, "tb_enabled": currentTBState])

    case "set_mode":
        guard let modeStr = req["mode"] as? String,
              let mode = AutoMode(rawValue: modeStr) else {
            return errorResponse("invalid mode")
        }
        autoEngine.mode = mode
        if let configData = req["config"] as? [String: Any] {
            if let temp = configData["temp_threshold"] as? Double {
                autoEngine.config.tempThreshold = temp
            }
            if let hys = configData["temp_hysteresis"] as? Double {
                autoEngine.config.tempHysteresis = hys
            }
            if let batt = configData["battery_threshold"] as? Int {
                autoEngine.config.batteryThreshold = batt
            }
        }
        return jsonResponse(["success": true, "mode": mode.rawValue])

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
    let sensors = sensorMonitor.readSensors()
    let load = cpuStats.getLoad()
    let batt = currentBatteryLevel()
    let loaded = kextManager.isLoaded

    return jsonResponse([
        "success": true,
        "tb_enabled": currentTBState,
        "cpu_temp": sensors?.cpuTemp ?? 0,
        "fan_speed": sensors?.fanSpeed ?? 0,
        "cpu_load": load,
        "mode": autoEngine.mode.rawValue,
        "kext_loaded": loaded,
        "battery_level": batt,
    ])
}

func currentBatteryLevel() -> Int {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty,
              let desc = IOPSGetPowerSourceDescription(blob, list[0])?.takeUnretainedValue() as? [String: Any],
              let level = desc[kIOPSCurrentCapacityKey as String] as? Int else {
        return -1
    }
    return level
}

func jsonResponse(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
}

func errorResponse(_ msg: String) -> String {
    return jsonResponse(["success": false, "error": msg])
}

signal(SIGPIPE, SIG_IGN)

guard ipc.start() else {
    print("ERROR: Failed to start IPC server")
    exit(1)
}

print("TBControl daemon started")
autoEngine.onAction = { shouldEnable in
    if shouldEnable {
        _ = kextManager.unload()
    } else {
        _ = kextManager.load()
    }
    currentTBState = shouldEnable
}

Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    guard autoEngine.mode != .manual else { return }
    guard let sensors = sensorMonitor.readSensors() else { return }
    let load = cpuStats.getLoad()
    let batt = currentBatteryLevel()

    if let action = autoEngine.evaluate(cpuTemp: sensors.cpuTemp, cpuLoad: load,
                                         batteryLevel: batt >= 0 ? batt : nil,
                                         runningApps: []) {
        autoEngine.onAction?(action)
    }
}

RunLoop.main.run()
