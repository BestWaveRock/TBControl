import Foundation

enum AutoMode: String, Codable {
    case manual
    case autoTemp = "auto_temp"
    case autoBattery = "auto_battery"
}

struct AutoConfig: Codable {
    var tempThreshold: Double = 75.0
    var tempHysteresis: Double = 10.0
    var batteryThreshold: Int = 30
    var monitorApps: [String] = []
}

class AutoModeEngine {
    var mode: AutoMode = .manual
    var config: AutoConfig = AutoConfig()
    var onAction: ((Bool) -> Void)?

    private var lastAction: Bool? = nil

    func evaluate(cpuTemp: Double, cpuLoad: Double, batteryLevel: Int?, runningApps: [String]) -> Bool? {
        switch mode {
        case .manual:
            return nil

        case .autoTemp:
            if let last = lastAction {
                if last == false && cpuTemp < (config.tempThreshold - config.tempHysteresis) {
                    lastAction = true
                    return true
                } else if last == true && cpuTemp > config.tempThreshold {
                    lastAction = false
                    return false
                }
            } else {
                if cpuTemp > config.tempThreshold {
                    lastAction = false
                    return false
                } else {
                    lastAction = true
                    return true
                }
            }
            return nil

        case .autoBattery:
            guard let level = batteryLevel else { return nil }
            let shouldDisable = level <= config.batteryThreshold
            if lastAction != shouldDisable {
                lastAction = shouldDisable
                return !shouldDisable
            }
            return nil
        }
    }
}
