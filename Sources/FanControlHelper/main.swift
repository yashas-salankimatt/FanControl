import Foundation
import SMCKit
#if canImport(Darwin)
import Darwin
#endif

// MARK: - FanControl Privileged Helper Daemon
//
// This daemon runs as root via a LaunchDaemon and listens on a Unix domain
// socket for commands from the FanControl app. It handles all SMC write
// operations that require elevated privileges.

let smc = SMCConnection()
var fanManager: FanManager!

// MARK: - Main entry

fputs("FanControl Helper starting (pid \(getpid()))...\n", stderr)

do {
    try smc.open()
    fputs("SMC connection opened.\n", stderr)
} catch {
    fputs("Failed to open SMC: \(error.localizedDescription)\n", stderr)
    Foundation.exit(1)
}

fanManager = FanManager(smc: smc)

// Signal handling
signal(SIGTERM) { _ in
    try? fanManager.setAllAutoMode()
    smc.close()
    unlink(helperSocketPath)
    Foundation.exit(0)
}
signal(SIGINT) { _ in
    try? fanManager.setAllAutoMode()
    smc.close()
    unlink(helperSocketPath)
    Foundation.exit(0)
}

// MARK: - Socket server

func createListeningSocket() -> Int32 {
    // Remove stale socket file
    unlink(helperSocketPath)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        fputs("Failed to create socket: \(String(cString: strerror(errno)))\n", stderr)
        Foundation.exit(1)
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = helperSocketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
            for i in 0..<min(pathBytes.count, 104) {
                dest[i] = pathBytes[i]
            }
        }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard bindResult == 0 else {
        fputs("Failed to bind socket: \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        Foundation.exit(1)
    }

    // Allow non-root users to connect
    chmod(helperSocketPath, 0o666)

    guard listen(fd, 5) == 0 else {
        fputs("Failed to listen: \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        Foundation.exit(1)
    }

    return fd
}

func handleCommand(_ command: HelperCommand) -> HelperResponse {
    switch command {
    case .ping:
        return .ok()

    case .setFanMode(let fanIndex, let manual):
        do {
            if manual {
                try smc.writeValue("F\(fanIndex)Md", value: 1)
            } else {
                try smc.writeValue("F\(fanIndex)Md", value: 0)
            }
            return .ok()
        } catch {
            return .fail(error.localizedDescription)
        }

    case .setFanSpeed(let fanIndex, let percentage):
        do {
            try fanManager.setFanSpeed(index: fanIndex, percentage: percentage)
            return .ok()
        } catch {
            return .fail(error.localizedDescription)
        }

    case .setFanRPM(let fanIndex, let rpm):
        do {
            try fanManager.setFanRPM(index: fanIndex, rpm: rpm)
            return .ok()
        } catch {
            return .fail(error.localizedDescription)
        }

    case .setAllAuto:
        do {
            try fanManager.setAllAutoMode()
            return .ok()
        } catch {
            return .fail(error.localizedDescription)
        }
    }
}

func handleClient(_ clientFD: Int32) {
    defer { close(clientFD) }

    // Set a read timeout
    var tv = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    // Read and process commands until the client disconnects
    while true {
        guard let command = readFrame(fd: clientFD, as: HelperCommand.self) else {
            break
        }
        let response = handleCommand(command)
        if !writeFrame(fd: clientFD, value: response) {
            break
        }
    }
}

// MARK: - Start server

let serverFD = createListeningSocket()
fputs("Listening on \(helperSocketPath)\n", stderr)

// Accept loop
while true {
    let clientFD = accept(serverFD, nil, nil)
    guard clientFD >= 0 else {
        if errno == EINTR { continue }
        fputs("Accept error: \(String(cString: strerror(errno)))\n", stderr)
        continue
    }

    // Handle each client in a background thread
    DispatchQueue.global().async {
        handleClient(clientFD)
    }
}
