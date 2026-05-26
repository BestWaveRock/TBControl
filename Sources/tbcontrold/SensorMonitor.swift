import Foundation
import Csmc

struct SensorData {
    let cpuTemp: Double
    let fanSpeed: Int
}

class SensorMonitor {
    func readSensors() -> SensorData? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        task.arguments = ["--samplers", "smc", "-n", "1", "-i", "0"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()

        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit(timeout: 3)

        guard task.isRunning == false || task.terminationStatus == 0 else { return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        let result = parseSensorOutput(output)
        if result != nil { return result }

        return thermalLevelFallback()
    }

    private func parseSensorOutput(_ output: String) -> SensorData? {
        var temp: Double = 0
        var fan: Int = 0
        var foundTemp = false
        var foundFan = false

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.lowercased().contains("cpu die temperature") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    let valStr = parts[1].trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "°C", with: " ")
                        .replacingOccurrences(of: "C", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: " ").first ?? ""
                    if let t = Double(valStr) {
                        temp = t
                        foundTemp = true
                    }
                }
            }

            if trimmed.lowercased().hasPrefix("fan") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    let valStr = parts[1].trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "rpm", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let f = Int(valStr) {
                        fan = f
                        foundFan = true
                    }
                }
            }
        }

        guard foundTemp || foundFan else { return nil }
        return SensorData(cpuTemp: temp, fanSpeed: fan)
    }

    private func readFanFromSMC() -> Int? {
        var rpm: Int32 = 0
        guard smc_get_fan_speed(&rpm) == 0, rpm > 0 else { return nil }
        return Int(rpm)
    }

    private func thermalLevelFallback() -> SensorData? {
        if let fan = readFanFromSMC() {
            return SensorData(cpuTemp: 0, fanSpeed: fan)
        }
        let name = "machdep.xcpm.cpu_thermal_level"
        let cName = (name as NSString).utf8String!
        var size = 0
        guard sysctlbyname(cName, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var level: UInt32 = 0
        var newSize = size
        guard sysctlbyname(cName, &level, &newSize, nil, 0) == 0 else { return nil }
        let temp = Double(level) / 127.0 * 100.0
        return SensorData(cpuTemp: temp, fanSpeed: 0)
    }
}
