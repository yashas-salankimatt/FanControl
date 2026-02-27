import Foundation

// MARK: - Helper Protocol

/// Socket path for communication between the app and the privileged helper.
public let helperSocketPath = "/var/run/fancontrol.sock"

/// Commands sent from the app to the helper daemon.
public enum HelperCommand: Codable, Sendable {
    case ping
    case setFanMode(fanIndex: Int, manual: Bool)
    case setFanSpeed(fanIndex: Int, percentage: Double)
    case setFanRPM(fanIndex: Int, rpm: Double)
    case setAllAuto
}

/// Responses sent from the helper back to the app.
public struct HelperResponse: Codable, Sendable {
    public let success: Bool
    public let error: String?

    public static func ok() -> HelperResponse {
        HelperResponse(success: true, error: nil)
    }

    public static func fail(_ message: String) -> HelperResponse {
        HelperResponse(success: false, error: message)
    }
}

// MARK: - Wire format helpers

/// Encode a message as a length-prefixed JSON frame: [4-byte big-endian length][JSON data]
public func encodeFrame<T: Encodable>(_ value: T) throws -> Data {
    let json = try JSONEncoder().encode(value)
    var length = UInt32(json.count).bigEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(json)
    return frame
}

/// Read exactly `count` bytes from a file descriptor. Returns nil on EOF/error.
public func readExact(fd: Int32, count: Int) -> Data? {
    var buffer = [UInt8](repeating: 0, count: count)
    var totalRead = 0
    while totalRead < count {
        let n = read(fd, &buffer[totalRead], count - totalRead)
        if n <= 0 { return nil }
        totalRead += n
    }
    return Data(buffer)
}

/// Read a length-prefixed JSON frame from a file descriptor.
public func readFrame<T: Decodable>(fd: Int32, as type: T.Type) -> T? {
    guard let lenData = readExact(fd: fd, count: 4) else { return nil }
    let length = lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    guard length > 0, length < 1_000_000 else { return nil }
    guard let jsonData = readExact(fd: fd, count: Int(length)) else { return nil }
    return try? JSONDecoder().decode(type, from: jsonData)
}

/// Write a length-prefixed JSON frame to a file descriptor.
public func writeFrame<T: Encodable>(fd: Int32, value: T) -> Bool {
    guard let frame = try? encodeFrame(value) else { return false }
    return frame.withUnsafeBytes { buf in
        let ptr = buf.baseAddress!
        var totalWritten = 0
        while totalWritten < frame.count {
            let n = write(fd, ptr + totalWritten, frame.count - totalWritten)
            if n <= 0 { return false }
            totalWritten += n
        }
        return true
    }
}
