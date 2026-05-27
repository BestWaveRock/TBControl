import Foundation

class IPCClient {
    private let socketPath = "/tmp/tbcontrol.sock"

    func sendCommand(_ dict: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return sendData(data)
    }

    func getStatus() -> StatusInfo? {
        guard let resp = sendCommand(["cmd": "status"]),
              let success = resp["success"] as? Bool, success else { return nil }
        return StatusInfo(
            tbEnabled: resp["tb_enabled"] as? Bool ?? true,
            cpuTemp: resp["cpu_temp"] as? Double,
            fanSpeed: resp["fan_speed"] as? Int,
            cpuLoad: resp["cpu_load"] as? Double ?? 0,
            mode: resp["mode"] as? String ?? "manual",
            batteryLevel: resp["battery_level"] as? Int ?? -1
        )
    }

    func setTurboBoost(enabled: Bool) -> Bool {
        guard let resp = sendCommand(["cmd": "set_tb", "enabled": enabled]),
              let success = resp["success"] as? Bool else { return false }
        return success
    }

    func setMode(_ mode: String, config: [String: Any] = [:]) -> Bool {
        var cmd: [String: Any] = ["cmd": "set_mode", "mode": mode]
        if !config.isEmpty { cmd["config"] = config }
        guard let resp = sendCommand(cmd), let success = resp["success"] as? Bool else { return false }
        return success
    }

    private func sendData(_ data: Data) -> [String: Any]? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCString = (socketPath as NSString).utf8String!
        strncpy(&addr.sun_path.0, pathCString, Int(MemoryLayout.size(ofValue: addr.sun_path)) - 1)

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        let timeout: TimeInterval = 3
        var writeData = data
        writeData.append(contentsOf: [0x0a])
        writeData.withUnsafeBytes { ptr in
            var remaining = writeData.count
            var offset = 0
            while remaining > 0 {
                let n = write(sock, ptr.baseAddress!.advanced(by: offset), remaining)
                if n <= 0 { break }
                remaining -= n
                offset += n
            }
        }

        shutdown(sock, SHUT_WR)

        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let n = read(sock, &buf, buf.count)
            if n <= 0 { break }
            responseData.append(buf, count: n)
        }

        guard !responseData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }
        return json
    }
}

struct StatusInfo {
    let tbEnabled: Bool
    let cpuTemp: Double?
    let fanSpeed: Int?
    let cpuLoad: Double
    let mode: String
    let batteryLevel: Int
}
