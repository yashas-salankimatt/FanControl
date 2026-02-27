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
var fanCount: Int = 0

/// Serial queue to serialize all SMC access (SMCConnection is not reentrant)
let smcQueue = DispatchQueue(label: "com.fancontrol.helper.smc")

// MARK: - Main entry

// Ignore SIGPIPE — handle EPIPE from write() instead of crashing
signal(SIGPIPE, SIG_IGN)

fputs("FanControl Helper starting (pid \(getpid()))...\n", stderr)

do {
    try smc.open()
    fputs("SMC connection opened.\n", stderr)
} catch {
    fputs("Failed to open SMC: \(error.localizedDescription)\n", stderr)
    Foundation.exit(1)
}

fanManager = FanManager(smc: smc)

// Read fan count once at startup for input validation
fanCount = (try? fanManager.getFanCount()) ?? 0
fputs("Detected \(fanCount) fan(s).\n", stderr)

// Signal handling via DispatchSource (async-signal-safe)
let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: smcQueue)
sigTermSource.setEventHandler {
    fputs("Received SIGTERM, restoring auto mode...\n", stderr)
    try? fanManager.setAllAutoMode()
    smc.close()
    unlink(helperSocketPath)
    Foundation.exit(0)
}
sigTermSource.resume()
signal(SIGTERM, SIG_IGN)

let sigIntSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: smcQueue)
sigIntSource.setEventHandler {
    fputs("Received SIGINT, restoring auto mode...\n", stderr)
    try? fanManager.setAllAutoMode()
    smc.close()
    unlink(helperSocketPath)
    Foundation.exit(0)
}
sigIntSource.resume()
signal(SIGINT, SIG_IGN)

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
        let capacity = MemoryLayout.size(ofValue: ptr.pointee)
        ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
            for i in 0..<min(pathBytes.count, capacity) {
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

    // Restrict socket to root:staff (console users on macOS are in the staff group)
    chown(helperSocketPath, 0, 20)  // root:staff (GID 20 = staff on macOS)
    chmod(helperSocketPath, 0o660)

    guard listen(fd, 5) == 0 else {
        fputs("Failed to listen: \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        Foundation.exit(1)
    }

    return fd
}

func validateFanIndex(_ index: Int) -> HelperResponse? {
    guard index >= 0 && index < fanCount else {
        return .fail("Invalid fan index \(index) (have \(fanCount) fans)")
    }
    return nil
}

func handleCommand(_ command: HelperCommand) -> HelperResponse {
    // Serialize all SMC access
    return smcQueue.sync {
        switch command {
        case .ping:
            return .ok()

        case .setFanMode(let fanIndex, let manual):
            if let err = validateFanIndex(fanIndex) { return err }
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
            if let err = validateFanIndex(fanIndex) { return err }
            do {
                try fanManager.setFanSpeed(index: fanIndex, percentage: percentage)
                return .ok()
            } catch {
                return .fail(error.localizedDescription)
            }

        case .setFanRPM(let fanIndex, let rpm):
            if let err = validateFanIndex(fanIndex) { return err }
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
