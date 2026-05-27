import Foundation

class KextManager {
    static let kextIdentifier = "com.tbcontrol.DisableTurboBoost"
    private let kextPath: String

    init(kextPath: String) {
        self.kextPath = kextPath
    }

    private var lastLoadedCheck: (Date, Bool)? = nil
    private let lock = NSLock()
    var isLoaded: Bool {
        lock.lock()
        if let last = lastLoadedCheck, Date().timeIntervalSince(last.0) < 2.0 {
            let result = last.1
            lock.unlock()
            return result
        }
        lock.unlock()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
        task.arguments = ["-b", Self.kextIdentifier]

        let out = Pipe()
        let err = Pipe() // Sink for stderr
        task.standardOutput = out
        task.standardError = err

        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.contains(Self.kextIdentifier) == true
        
        lock.lock()
        lastLoadedCheck = (Date(), result)
        lock.unlock()
        
        return result
    }

    func checkSIP() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        task.arguments = ["status"]
        let out = Pipe()
        task.standardOutput = out
        try? task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // If it says "enabled", SIP is on.
        return output.contains("disabled")
    }

    func load() -> Bool {
        guard !isLoaded else { return true }

        // SIP check is mandatory for unsigned kexts on modern macOS
        if !checkSIP() {
            print("ERROR: SIP is enabled. Unsigned kexts cannot be loaded.")
            return false
        }

        // Ensure correct ownership and permissions
        let setup = Process()
        setup.executableURL = URL(fileURLWithPath: "/bin/bash")
        setup.arguments = ["-c", "chown -R root:wheel '\(kextPath)' && chmod -R 755 '\(kextPath)'"]
        try? setup.run()
        setup.waitUntilExit()

        // Use kmutil on macOS 11+
        let task = Process()
        if #available(macOS 11.0, *) {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/kmutil")
            task.arguments = ["load", "-p", kextPath]
        } else {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/kextutil")
            task.arguments = ["-v", kextPath]
        }
        
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        
        do {
            try task.run()
        } catch {
            print("Failed to run load command: \(error)")
            return false
        }
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            print("Kext load failed (status \(task.terminationStatus)): \(msg)")
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
        
        do {
            try task.run()
        } catch {
            print("Failed to run kextunload: \(error)")
            return false
        }
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            print("Kext unload failed (status \(task.terminationStatus)): \(msg)")
            return false
        }
        return true
    }
}
