import Foundation

enum AutoMode: String, Codable {
    case manual
    case autoTemp = "auto_temp"
    case autoBattery = "auto_battery"
    case autoLoad = "auto_load"
    case autoFan = "auto_fan"
}

struct AutoConfig: Codable {
    var tempThreshold: Double = 75.0
    var tempHysteresis: Double = 10.0
    var batteryThreshold: Int = 30
    var loadThreshold: Double = 75.0
    var loadDurationSeconds: Int = 10
    var fanHighThreshold: Int = 5500
    var fanLowThreshold: Int = 4000
    var fanLowDurationSeconds: Int = 10
    var monitorApps: [String] = []
}

class AutoModeEngine {
    private var _mode: AutoMode = .manual
    private let lock = NSLock()
    var mode: AutoMode {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _mode
        }
        set {
            lock.lock()
            _mode = newValue
            lock.unlock()
        }
    }
    private var _config: AutoConfig = AutoConfig()
    var config: AutoConfig {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _config
        }
        set {
            lock.lock()
            _config = newValue
            lock.unlock()
        }
    }
    var onAction: ((Bool) -> Void)?

    private var lastAction: Bool? = nil
    private var highLoadStartTime: Date? = nil
    private var lowFanStartTime: Date? = nil

    func evaluate(cpuTemp: Double, cpuLoad: Double, fanSpeed: Int, batteryLevel: Int?, isPluggedIn: Bool, runningApps: [String]) -> Bool? {
        switch mode {
        case .manual:
            highLoadStartTime = nil
            lowFanStartTime = nil
            return nil

        case .autoTemp:
            highLoadStartTime = nil
            lowFanStartTime = nil
            guard cpuTemp > 0 else { return nil }
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
            highLoadStartTime = nil
            lowFanStartTime = nil
            if isPluggedIn {
                if lastAction != true {
                    lastAction = true
                    return true
                }
                return nil
            }
            guard let level = batteryLevel else { return nil }
            let shouldDisable = level <= config.batteryThreshold
            if lastAction != !shouldDisable {
                lastAction = !shouldDisable
                return !shouldDisable
            }
            return nil

        case .autoLoad:
            lowFanStartTime = nil
            if cpuLoad >= config.loadThreshold {
                if highLoadStartTime == nil {
                    highLoadStartTime = Date()
                } else if let startTime = highLoadStartTime, Date().timeIntervalSince(startTime) >= Double(config.loadDurationSeconds) {
                    if lastAction != false {
                        lastAction = false
                        return false // Disable Turbo Boost
                    }
                }
            } else {
                highLoadStartTime = nil
                if lastAction != true {
                    lastAction = true
                    return true // Enable Turbo Boost
                }
            }
            return nil
            
        case .autoFan:
            highLoadStartTime = nil
            // Disable Turbo Boost when fan speed > 5500 RPM
            if fanSpeed > config.fanHighThreshold {
                lowFanStartTime = nil
                if lastAction != false {
                    lastAction = false
                    return false
                }
            }
            // Enable Turbo Boost when fan speed < 4000 RPM for 10 seconds
            else if fanSpeed < config.fanLowThreshold {
                if lowFanStartTime == nil {
                    lowFanStartTime = Date()
                } else if let startTime = lowFanStartTime, Date().timeIntervalSince(startTime) >= Double(config.fanLowDurationSeconds) {
                    if lastAction != true {
                        lastAction = true
                        lowFanStartTime = nil
                        return true
                    }
                }
            } else {
                // Fan speed in normal range, reset the timer
                lowFanStartTime = nil
            }
            return nil
        }
    }
}
