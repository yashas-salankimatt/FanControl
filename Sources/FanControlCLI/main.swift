import Foundation
import SMCKit
import CSMCTypes

func pad(_ s: String, to width: Int) -> String {
    if s.count >= width { return s }
    return s + String(repeating: " ", count: width - s.count)
}

print("FanControl CLI")
print("==============")
assert(MemoryLayout<SMCParamStruct>.size == 80, "Struct must be 80 bytes")

let smc = SMCConnection()
do { try smc.open() } catch { print("Cannot open SMC: \(error)"); exit(1) }

let keyCount = (try? smc.getKeyCount()) ?? 0
print("SMC keys: \(keyCount)")
print()

// Fans
print("=== FANS ===")
let fanManager = FanManager(smc: smc)
let fanCount = (try? fanManager.getFanCount()) ?? 0
print("Fan count: \(fanCount)\n")
for i in 0..<fanCount {
    if let fan = try? fanManager.getFanInfo(i) {
        let pct = Int(fan.currentPercent.rounded())
        print("Fan \(i): \(Int(fan.currentRPM)) RPM (\(pct)%) [min:\(Int(fan.minRPM)) max:\(Int(fan.maxRPM)) target:\(Int(fan.targetRPM))] mode:\(fan.isForced ? "manual" : "auto")")
    }
}

// Temperatures
print("\n=== TEMPERATURES ===")
let tempManager = TemperatureManager(smc: smc)
if let sensors = try? tempManager.discoverTemperatureSensors() {
    let meaningful = sensors.filter { $0.temperature > 5.0 }
    print("\(meaningful.count) active sensors (of \(sensors.count) total):\n")
    for s in meaningful {
        print("  \(pad(s.key, to: 5)) \(pad(s.name, to: 28)) \(Int(s.temperature.rounded()))C")
    }
}

// Fan control test
if CommandLine.arguments.contains("--test-fan") {
    print("\n=== FAN CONTROL TEST ===")
    guard fanCount > 0 else { print("No fans!"); exit(0) }

    do {
        let before = try fanManager.getFanInfo(0)
        print("Before: \(Int(before.currentRPM)) RPM, mode=\(before.isForced ? "manual" : "auto")")

        print("Setting fan 0 to 50%...")
        try fanManager.setFanSpeed(index: 0, percentage: 50)
        print("Target set. Monitoring for 8 seconds...")
        for t in 1...8 {
            Thread.sleep(forTimeInterval: 1.0)
            let cur = try fanManager.getFanInfo(0)
            print("  \(t)s: \(Int(cur.currentRPM)) RPM (target: \(Int(cur.targetRPM)))")
        }

        print("\nSetting fan 0 to 100%...")
        try fanManager.setFanSpeed(index: 0, percentage: 100)
        for t in 1...8 {
            Thread.sleep(forTimeInterval: 1.0)
            let cur = try fanManager.getFanInfo(0)
            print("  \(t)s: \(Int(cur.currentRPM)) RPM")
        }

        print("\nRestoring auto mode...")
        try fanManager.setAutoMode(index: 0)
        Thread.sleep(forTimeInterval: 2.0)
        let after = try fanManager.getFanInfo(0)
        print("After: \(Int(after.currentRPM)) RPM, mode=\(after.isForced ? "manual" : "auto")")
        print("[OK] Fan control test complete!")
    } catch {
        print("[FAIL] \(error)")
        print("Fan control requires root: sudo .build/debug/FanControlCLI --test-fan")
        try? fanManager.setAllAutoMode()
    }
} else {
    print("\nRun with --test-fan to test fan control (requires sudo)")
}

smc.close()
