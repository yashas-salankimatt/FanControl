import Foundation

public struct FanInfo: Sendable {
    public let index: Int
    public let name: String
    public let currentRPM: Double
    public let minRPM: Double
    public let maxRPM: Double
    public let targetRPM: Double
    public let mode: UInt8  // 0 = auto, 1 = forced/manual

    public var isForced: Bool { mode != 0 }

    public var currentPercent: Double {
        guard maxRPM > minRPM else { return 0 }
        return ((currentRPM - minRPM) / (maxRPM - minRPM)) * 100.0
    }
}

public class FanManager {
    private let smc: SMCConnection

    public init(smc: SMCConnection) {
        self.smc = smc
    }

    public func getFanCount() throws -> Int {
        let value = try smc.readKey("FNum")
        return Int(value.toDouble() ?? 0)
    }

    public func getFanInfo(_ index: Int) throws -> FanInfo {
        let current = try smc.readKey("F\(index)Ac").toDouble() ?? 0
        let min = try smc.readKey("F\(index)Mn").toDouble() ?? 0
        let max = try smc.readKey("F\(index)Mx").toDouble() ?? 0
        let target = try smc.readKey("F\(index)Tg").toDouble() ?? 0
        let mode = UInt8(try smc.readKey("F\(index)Md").toDouble() ?? 0)

        return FanInfo(
            index: index,
            name: "Fan \(index)",
            currentRPM: current,
            minRPM: min,
            maxRPM: max,
            targetRPM: target,
            mode: mode
        )
    }

    public func getAllFans() throws -> [FanInfo] {
        let count = try getFanCount()
        var fans: [FanInfo] = []
        for i in 0..<count {
            if let fan = try? getFanInfo(i) {
                fans.append(fan)
            }
        }
        return fans
    }

    /// Set fan speed as a percentage (0-100). Sets fan to forced/manual mode.
    public func setFanSpeed(index: Int, percentage: Double) throws {
        let info = try getFanInfo(index)
        let clamped = max(0, min(100, percentage))
        let targetRPM = info.minRPM + (info.maxRPM - info.minRPM) * (clamped / 100.0)

        // Set manual mode (F{n}Md = 1) - Apple Silicon uses per-fan mode
        try smc.writeValue("F\(index)Md", value: 1)
        try smc.writeValue("F\(index)Tg", value: targetRPM)
    }

    /// Set fan speed as absolute RPM. Sets fan to forced/manual mode.
    public func setFanRPM(index: Int, rpm: Double) throws {
        try smc.writeValue("F\(index)Md", value: 1)
        try smc.writeValue("F\(index)Tg", value: rpm)
    }

    /// Return fan to automatic (system-managed) mode.
    public func setAutoMode(index: Int) throws {
        try smc.writeValue("F\(index)Md", value: 0)
    }

    /// Return all fans to automatic mode.
    public func setAllAutoMode() throws {
        let count = try getFanCount()
        for i in 0..<count {
            try? smc.writeValue("F\(i)Md", value: 0)
        }
    }
}
