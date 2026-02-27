import Foundation

public struct FanCurvePoint: Codable, Identifiable, Sendable {
    public var id: UUID
    public var temperature: Double
    public var fanSpeedPercent: Double

    public init(temperature: Double, fanSpeedPercent: Double) {
        self.id = UUID()
        self.temperature = temperature
        self.fanSpeedPercent = fanSpeedPercent
    }
}

public struct TemperatureLimitMode: Codable, Sendable {
    /// Temperature (Celsius) where fans should stay quiet/minimum.
    public var comfortTemperature: Double
    /// Temperature (Celsius) that should not be exceeded (fans at 100%).
    public var maxTemperature: Double

    public init(comfortTemperature: Double, maxTemperature: Double) {
        self.comfortTemperature = comfortTemperature
        self.maxTemperature = maxTemperature
    }

    /// Generate a 3-point curve: 0% at comfort, 50% at midpoint, 100% at max.
    public func generatePoints() -> [FanCurvePoint] {
        let mid = (comfortTemperature + maxTemperature) / 2.0
        return [
            FanCurvePoint(temperature: comfortTemperature, fanSpeedPercent: 0),
            FanCurvePoint(temperature: mid, fanSpeedPercent: 50),
            FanCurvePoint(temperature: maxTemperature, fanSpeedPercent: 100),
        ]
    }
}

public struct FanCurveConfig: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var temperatureSensorKey: String
    public var fanIndices: [Int]
    public var points: [FanCurvePoint]
    public var enabled: Bool
    public var limitMode: TemperatureLimitMode?

    public init(name: String, temperatureSensorKey: String, fanIndices: [Int], points: [FanCurvePoint], enabled: Bool = true, limitMode: TemperatureLimitMode? = nil) {
        self.id = UUID()
        self.name = name
        self.temperatureSensorKey = temperatureSensorKey
        self.fanIndices = fanIndices
        self.points = points
        self.enabled = enabled
        self.limitMode = limitMode
    }

    /// If this is a limit-mode curve, regenerate points from the limit parameters.
    public mutating func regeneratePointsIfNeeded() {
        if let limit = limitMode {
            self.points = limit.generatePoints()
        }
    }

    /// Interpolate fan speed percentage for a given temperature.
    public func interpolate(temperature: Double) -> Double {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard !sorted.isEmpty else { return 0 }

        if temperature <= sorted.first!.temperature {
            return sorted.first!.fanSpeedPercent
        }
        if temperature >= sorted.last!.temperature {
            return sorted.last!.fanSpeedPercent
        }

        for i in 0..<sorted.count - 1 {
            let p1 = sorted[i]
            let p2 = sorted[i + 1]
            if temperature >= p1.temperature && temperature <= p2.temperature {
                let ratio = (temperature - p1.temperature) / (p2.temperature - p1.temperature)
                return p1.fanSpeedPercent + ratio * (p2.fanSpeedPercent - p1.fanSpeedPercent)
            }
        }

        return sorted.last!.fanSpeedPercent
    }
}

/// Persistent storage for fan curve configurations.
public class FanCurveStore {
    private let fileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FanControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("curves.json")
    }

    public func load() -> [FanCurveConfig] {
        guard let data = try? Data(contentsOf: fileURL),
              let curves = try? JSONDecoder().decode([FanCurveConfig].self, from: data) else {
            return []
        }
        return curves
    }

    public func save(_ curves: [FanCurveConfig]) {
        guard let data = try? JSONEncoder().encode(curves) else { return }
        try? data.write(to: fileURL)
    }
}
