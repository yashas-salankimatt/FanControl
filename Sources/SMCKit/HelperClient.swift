import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Client for communicating with the FanControlHelper privileged daemon.
public class HelperClient {
    private var fd: Int32 = -1
    private let lock = NSLock()

    public init() {}

    /// Check if the helper daemon is available.
    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: helperSocketPath)
    }

    /// Connect to the helper daemon. Returns true on success.
    @discardableResult
    private func connect() -> Bool {
        if fd >= 0 { close(fd) }

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

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

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result != 0 {
            close(fd)
            fd = -1
            return false
        }

        // Prevent SIGPIPE on broken socket — get EPIPE error instead
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // Set timeouts
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        return true
    }

    private func disconnect() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }

    /// Send a command to the helper and get the response.
    /// Thread-safe — serializes concurrent calls.
    public func send(_ command: HelperCommand) -> HelperResponse {
        lock.lock()
        defer { lock.unlock() }

        // Connect fresh for each command (simple and reliable)
        guard connect() else {
            return .fail("Cannot connect to helper daemon. Is it installed?")
        }
        defer { disconnect() }

        guard writeFrame(fd: fd, value: command) else {
            return .fail("Failed to send command to helper")
        }

        guard let response = readFrame(fd: fd, as: HelperResponse.self) else {
            return .fail("No response from helper")
        }

        return response
    }

    /// Ping the helper to verify it's running and responsive.
    public func ping() -> Bool {
        let response = send(.ping)
        return response.success
    }

    /// Set fan speed as a percentage (0-100).
    public func setFanSpeed(index: Int, percentage: Double) -> HelperResponse {
        send(.setFanSpeed(fanIndex: index, percentage: percentage))
    }

    /// Set fan to manual or auto mode.
    public func setFanMode(index: Int, manual: Bool) -> HelperResponse {
        send(.setFanMode(fanIndex: index, manual: manual))
    }

    /// Set fan speed as absolute RPM.
    public func setFanRPM(index: Int, rpm: Double) -> HelperResponse {
        send(.setFanRPM(fanIndex: index, rpm: rpm))
    }

    /// Return all fans to automatic mode.
    public func setAllAuto() -> HelperResponse {
        send(.setAllAuto)
    }
}
