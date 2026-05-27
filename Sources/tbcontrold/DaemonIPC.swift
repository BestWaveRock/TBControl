import Foundation

class DaemonIPC {
    private let socketPath = "/tmp/tbcontrol.sock"
    private var serverHandle: Int32?
    private var onRequest: ((String, Int32) -> String?)?

    init(onRequest: ((String, Int32) -> String?)?) {
        self.onRequest = onRequest
    }

    func start() -> Bool {
        unlink(socketPath)

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            print("Failed to create socket")
            return false
        }
        serverHandle = sock

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCString = (socketPath as NSString).utf8String!
        strncpy(&addr.sun_path.0, pathCString, Int(MemoryLayout.size(ofValue: addr.sun_path)) - 1)

        let addrSize = MemoryLayout<sockaddr_un>.size
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(addrSize))
            }
        }

        guard bindResult == 0 else {
            print("Bind failed: \(errno)")
            close(sock)
            return false
        }

        chmod(socketPath, 0o666)

        let listenResult = listen(sock, 5)
        guard listenResult == 0 else {
            print("Listen failed: \(errno)")
            close(sock)
            return false
        }

        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.acceptLoop()
        }

        return true
    }

    private func acceptLoop() {
        guard let sock = serverHandle else { return }

        while true {
            let client = accept(sock, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                break
            }

            DispatchQueue.global(qos: .default).async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer {
            close(fd)
        }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 1024)

        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                data.append(buf, count: n)
                if data.contains(0x0a) { break }
            } else if n == 0 {
                break
            } else {
                if errno == EAGAIN || errno == EINTR { continue }
                return
            }
        }

        let reqStr = String(data: data, encoding: .utf8) ?? ""
        let trimmed = reqStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let respStr = onRequest?(trimmed, fd) ?? "{\"err\":\"no handler\"}"

        // 直接写入，不用withUnsafeBytes多次调用
        let cStr = (respStr as NSString).utf8String!
        let len = strlen(cStr)
        var remain = len
        var off = 0
        while remain > 0 {
            let n = write(fd, cStr + off, remain)
            if n <= 0 { break }
            remain -= n
            off += n
        }

    }

    func stop() {
        if let sock = serverHandle {
            close(sock)
        }
        unlink(socketPath)
    }
}

extension Process {
    func waitUntilExit(timeout: TimeInterval) {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            self.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            kill(self.processIdentifier, SIGKILL)
            self.waitUntilExit()
        }
    }
}
