import Foundation

class KextManager {
    static let kextIdentifier = "com.tbcontrol.DisableTurboBoost"
    private let kextPath: String

    init(kextPath: String) {
        self.kextPath = kextPath
    }

    var isLoaded: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
        task.arguments = ["-b", Self.kextIdentifier]

        let out = Pipe()
        task.standardOutput = out

        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.contains(Self.kextIdentifier) == true
    }

    func load() -> Bool {
        guard !isLoaded else { return true }

        let chown = Process()
        chown.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
        chown.arguments = ["-R", "root:wheel", kextPath]
        guard (try? chown.run()) != nil else { return false }
        chown.waitUntilExit()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/kextutil")
        task.arguments = ["-v", kextPath]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            print("Kext load failed: \(msg)")
            return false
        }
        return true
    }

    func unload() -> Bool {
        guard isLoaded else { return true }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/kextunload")
        task.arguments = ["-v", kextPath]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let msg = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("Kext unload failed: \(msg)")
            return false
        }
        return true
    }
}
