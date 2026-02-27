import Foundation
import IOKit
import CSMCTypes

// MARK: - Errors

public enum SMCError: LocalizedError {
    case serviceNotFound
    case openFailed(kern_return_t)
    case notOpen
    case callFailed(kern_return_t)
    case smcError(UInt8, String)
    case keyNotFound(String)
    case unsupportedDataType(String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service not found"
        case .openFailed(let code):
            return "Failed to open SMC connection: \(code)"
        case .notOpen:
            return "SMC connection not open"
        case .callFailed(let code):
            return "SMC call failed: 0x\(String(code, radix: 16))"
        case .smcError(let code, let key):
            return "SMC error 0x\(String(code, radix: 16)) for key '\(key)'"
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .unsupportedDataType(let type):
            return "Unsupported data type: \(type)"
        }
    }
}

// MARK: - Key/Type helpers

public func fourCC(_ s: String) -> UInt32 {
    let b = Array(s.utf8.prefix(4))
    guard b.count == 4 else { return 0 }
    return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
}

public func fourCCString(_ val: UInt32) -> String {
    let bytes = [
        UInt8((val >> 24) & 0xFF),
        UInt8((val >> 16) & 0xFF),
        UInt8((val >> 8) & 0xFF),
        UInt8(val & 0xFF)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

// MARK: - SMC Value

public struct SMCValue {
    public let key: String
    public let dataType: UInt32
    public let dataSize: UInt32
    public let rawBytes: [UInt8]

    public var dataTypeString: String { fourCCString(dataType) }

    /// Convert raw SMC bytes to a Double.
    /// On Apple Silicon, `flt ` type uses native little-endian byte order.
    /// Fixed-point and integer types use big-endian (network byte order).
    public func toDouble() -> Double? {
        let bytes = rawBytes
        guard !bytes.isEmpty else { return nil }

        switch dataTypeString {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            // Apple Silicon uses native (little-endian) byte order for floats
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))

        // Unsigned fixed point
        case "fp1f": return ufix16(bytes, frac: 15)
        case "fp2e": return ufix16(bytes, frac: 14)
        case "fp4c": return ufix16(bytes, frac: 12)
        case "fp5b": return ufix16(bytes, frac: 11)
        case "fp6a": return ufix16(bytes, frac: 10)
        case "fp79": return ufix16(bytes, frac: 9)
        case "fp88": return ufix16(bytes, frac: 8)
        case "fpa6": return ufix16(bytes, frac: 6)
        case "fpc4": return ufix16(bytes, frac: 4)
        case "fpe2": return ufix16(bytes, frac: 2)

        // Signed fixed point
        case "sp1e": return sfix16(bytes, frac: 14)
        case "sp2d": return sfix16(bytes, frac: 13)
        case "sp3c": return sfix16(bytes, frac: 12)
        case "sp4b": return sfix16(bytes, frac: 11)
        case "sp5a": return sfix16(bytes, frac: 10)
        case "sp69": return sfix16(bytes, frac: 9)
        case "sp78": return sfix16(bytes, frac: 8)
        case "sp87": return sfix16(bytes, frac: 7)
        case "sp96": return sfix16(bytes, frac: 6)
        case "spa5": return sfix16(bytes, frac: 5)
        case "spb4": return sfix16(bytes, frac: 4)
        case "spf0": return sfix16(bytes, frac: 0)

        // Integer types
        case "ui8 ": return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "si8 ": return Double(Int8(bitPattern: bytes[0]))
        case "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))

        default: return nil
        }
    }

    private func ufix16(_ b: [UInt8], frac: Int) -> Double? {
        guard b.count >= 2 else { return nil }
        let raw = UInt16(b[0]) << 8 | UInt16(b[1])
        return Double(raw) / Double(1 << frac)
    }

    private func sfix16(_ b: [UInt8], frac: Int) -> Double? {
        guard b.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))
        return Double(raw) / Double(1 << frac)
    }
}

// MARK: - SMC Connection

public class SMCConnection {
    private var connection: io_connect_t = 0
    private var isOpen = false
    private let lock = NSRecursiveLock()

    public init() {}

    public func open() throws {
        lock.lock()
        defer { lock.unlock() }

        if isOpen {
            IOServiceClose(connection)
            isOpen = false
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else {
            throw SMCError.serviceNotFound
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == kIOReturnSuccess else {
            throw SMCError.openFailed(result)
        }

        isOpen = true
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if isOpen {
            IOServiceClose(connection)
            isOpen = false
        }
    }

    deinit {
        close()
    }

    // MARK: - Low-level

    private func callSMC(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        lock.lock()
        defer { lock.unlock() }

        guard isOpen else { throw SMCError.notOpen }

        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMC_SELECTOR),
            &input,
            MemoryLayout<SMCParamStruct>.size,
            &output,
            &outputSize
        )

        guard result == kIOReturnSuccess else {
            throw SMCError.callFailed(result)
        }

        return output
    }

    // MARK: - Key info

    public struct KeyInfo {
        public let dataSize: UInt32
        public let dataType: UInt32
        public var dataTypeString: String { fourCCString(dataType) }
    }

    public func getKeyInfo(_ key: String) throws -> KeyInfo {
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = UInt8(SMC_CMD_READ_KEYINFO)

        let output = try callSMC(&input)
        guard output.result == 0 else {
            throw SMCError.smcError(output.result, key)
        }
        return KeyInfo(dataSize: output.keyInfo_dataSize, dataType: output.keyInfo_dataType)
    }

    // MARK: - Read

    public func readKey(_ key: String) throws -> SMCValue {
        let info = try getKeyInfo(key)

        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo_dataSize = info.dataSize
        input.data8 = UInt8(SMC_CMD_READ_BYTES)

        let output = try callSMC(&input)
        guard output.result == 0 else {
            throw SMCError.smcError(output.result, key)
        }

        // Extract value bytes from the fixed-size array
        let count = Int(info.dataSize)
        var bytes = [UInt8](repeating: 0, count: count)
        withUnsafeBytes(of: output.bytes) { buf in
            for i in 0..<min(count, 32) {
                bytes[i] = buf[i]
            }
        }

        return SMCValue(key: key, dataType: info.dataType, dataSize: info.dataSize, rawBytes: bytes)
    }

    // MARK: - Write

    public func writeBytes(_ key: String, bytes: [UInt8]) throws {
        let info = try getKeyInfo(key)

        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = UInt8(SMC_CMD_WRITE_BYTES)
        input.keyInfo_dataSize = info.dataSize

        withUnsafeMutableBytes(of: &input.bytes) { buf in
            for i in 0..<min(bytes.count, 32) {
                buf[i] = bytes[i]
            }
        }

        let output = try callSMC(&input)
        guard output.result == 0 else {
            throw SMCError.smcError(output.result, key)
        }
    }

    /// Write a floating-point value, automatically encoding for the key's data type.
    public func writeValue(_ key: String, value: Double) throws {
        let info = try getKeyInfo(key)
        let typeStr = fourCCString(info.dataType)

        var bytes: [UInt8]
        switch typeStr {
        case "flt ":
            let f = Float(value)
            let raw = f.bitPattern
            // Little-endian byte order for floats on Apple Silicon
            bytes = [UInt8(raw & 0xFF), UInt8((raw >> 8) & 0xFF), UInt8((raw >> 16) & 0xFF), UInt8(raw >> 24)]
        case "fpe2":
            let clamped = max(0, min(16383, value))
            let raw = UInt16(clamped * 4.0)
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "sp78":
            let clamped = max(-128, min(127, value))
            let raw = Int16(clamped * 256.0)
            let uraw = UInt16(bitPattern: raw)
            bytes = [UInt8(uraw >> 8), UInt8(uraw & 0xFF)]
        case "ui8 ":
            bytes = [UInt8(max(0, min(255, value)))]
        case "ui16":
            let clamped = max(0, min(65535, value))
            let raw = UInt16(clamped)
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            throw SMCError.unsupportedDataType(typeStr)
        }

        try writeBytes(key, bytes: bytes)
    }

    // MARK: - Key enumeration

    public func getKeyCount() throws -> Int {
        let value = try readKey("#KEY")
        return Int(value.toDouble() ?? 0)
    }

    public func getKeyFromIndex(_ index: Int) throws -> String {
        var input = SMCParamStruct()
        input.data8 = UInt8(SMC_CMD_READ_INDEX)
        input.data32 = UInt32(index)

        let output = try callSMC(&input)
        guard output.result == 0 else {
            throw SMCError.smcError(output.result, "#\(index)")
        }
        return fourCCString(output.key)
    }
}
