import Foundation

public struct TemperatureSensor: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let temperature: Double
    public let dataType: String
}

public class TemperatureManager {
    private let smc: SMCConnection
    private var discoveredKeys: [String] = []

    public init(smc: SMCConnection) {
        self.smc = smc
    }

    // Known temperature sensor names
    public static let knownSensors: [String: String] = [
        // CPU - Intel
        "TC0P": "CPU Proximity",
        "TC0D": "CPU Die",
        "TC0E": "CPU VRM",
        "TC0F": "CPU VRM 2",
        "TC1C": "CPU Core 1",
        "TC2C": "CPU Core 2",
        "TC3C": "CPU Core 3",
        "TC4C": "CPU Core 4",
        "TC5C": "CPU Core 5",
        "TC6C": "CPU Core 6",
        "TC7C": "CPU Core 7",
        "TC8C": "CPU Core 8",
        "TCXC": "CPU PECI",
        "TCSA": "CPU System Agent",
        "TCGC": "CPU/GPU (Integrated)",

        // CPU - Apple Silicon
        "Tp01": "CPU Efficiency Core 1",
        "Tp05": "CPU Efficiency Core 2",
        "Tp09": "CPU Efficiency Core 3",
        "Tp0D": "CPU Efficiency Core 4",
        "Tp0b": "CPU Performance Core 1",
        "Tp0f": "CPU Performance Core 2",
        "Tp0j": "CPU Performance Core 3",
        "Tp0n": "CPU Performance Core 4",
        "Tp0T": "CPU Performance Core 1 (2)",

        // GPU
        "TG0P": "GPU Proximity",
        "TG0D": "GPU Die",
        "TG0T": "GPU Thermal",
        "Tg05": "GPU Core 1",
        "Tg0D": "GPU Core 2",
        "Tg0L": "GPU Core 3",
        "Tg0T": "GPU Core 4",

        // Memory
        "TM0P": "Memory Proximity",
        "TM0S": "Memory Slot",
        "Tm00": "Memory Module 0",
        "Tm01": "Memory Module 1",
        "Tm02": "Memory Module 2",

        // Battery
        "TB0T": "Battery",
        "TB1T": "Battery 1",
        "TB2T": "Battery 2",

        // Storage
        "TH0P": "HDD/SSD Proximity",
        "TH0a": "SSD Temp A",
        "TH0b": "SSD Temp B",

        // Wireless & Misc
        "TW0P": "Wireless Module",
        "TN0P": "Northbridge Proximity",
        "TN0D": "Northbridge Die",
        "TP0P": "Power Supply",
        "Ts0P": "Palm Rest Left",
        "Ts1P": "Palm Rest Right",
        "TL0P": "LCD Proximity",
        "TA0P": "Ambient",
        "TI0P": "Thunderbolt",
        "TaLP": "Airflow Left",
        "TaRP": "Airflow Right",
        "Te05": "PCIe Slot 1",
        "Tw0P": "Airport",

        // Apple Silicon SoC
        "Tp1h": "SoC Temp 1",
        "Tp1t": "SoC Temp 2",
        "Tp1p": "SoC Temp 3",
        "Tp1l": "SoC Temp 4",

        // NAND
        "TN1D": "NAND Die",
    ]

    /// Discover all temperature sensors by scanning all SMC keys.
    public func discoverTemperatureSensors() throws -> [TemperatureSensor] {
        let totalKeys = try smc.getKeyCount()
        var sensors: [TemperatureSensor] = []
        var seenKeys = Set<String>()

        for i in 0..<totalKeys {
            guard let keyStr = try? smc.getKeyFromIndex(i) else { continue }

            // Temperature keys start with 'T' (uppercase or lowercase)
            let firstChar = keyStr.first ?? " "
            guard firstChar == "T" || firstChar == "t" else { continue }

            // Skip if already seen
            guard seenKeys.insert(keyStr).inserted else { continue }

            // Try to read and validate
            guard let value = try? smc.readKey(keyStr),
                  let temp = value.toDouble() else { continue }

            // Filter to reasonable temperature values (-20 to 150 °C)
            guard temp > -20 && temp < 150 else { continue }

            // Skip values that are exactly 0 (usually inactive/unused sensors)
            guard temp != 0 else { continue }

            let name = Self.knownSensors[keyStr] ?? keyStr
            let typeStr = fourCCString(value.dataType)

            sensors.append(TemperatureSensor(
                key: keyStr,
                name: name,
                temperature: temp,
                dataType: typeStr
            ))
        }

        discoveredKeys = sensors.map { $0.key }
        return sensors.sorted { $0.key < $1.key }
    }

    /// Re-read temperatures for previously discovered sensors. Much faster than full discovery.
    public func readTemperatures() throws -> [TemperatureSensor] {
        if discoveredKeys.isEmpty {
            return try discoverTemperatureSensors()
        }

        var sensors: [TemperatureSensor] = []
        for key in discoveredKeys {
            guard let value = try? smc.readKey(key),
                  let temp = value.toDouble(),
                  temp > -20 && temp < 150 else { continue }

            let name = Self.knownSensors[key] ?? key
            let typeStr = fourCCString(value.dataType)
            sensors.append(TemperatureSensor(key: key, name: name, temperature: temp, dataType: typeStr))
        }
        return sensors.sorted { $0.key < $1.key }
    }

    /// Read a single temperature sensor.
    public func readTemperature(_ key: String) throws -> Double? {
        let value = try smc.readKey(key)
        return value.toDouble()
    }
}
