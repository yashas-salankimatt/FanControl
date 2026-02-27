import Foundation
import SwiftUI
import SMCKit

enum MenuBarSensorMode: String, CaseIterable {
    case none
    case maxCPU
    case specific
}

@MainActor
class AppState: ObservableObject {
    @Published var fans: [FanInfo] = []
    @Published var temperatures: [TemperatureSensor] = []
    @Published var curves: [FanCurveConfig] = []
    @Published var manualSpeeds: [Int: Double] = [:]  // fanIndex -> percentage
    @Published var manualEnabled: [Int: Bool] = [:]    // fanIndex -> isManual
    @Published var isPrivileged: Bool = false
    @Published var helperConnected: Bool = false
    @Published var lastError: String?
    @Published var helperInstalling: Bool = false
    @Published var useFahrenheit: Bool = UserDefaults.standard.bool(forKey: "useFahrenheit") {
        didSet { UserDefaults.standard.set(useFahrenheit, forKey: "useFahrenheit") }
    }
    @Published var menuBarSensorMode: MenuBarSensorMode = {
        let raw = UserDefaults.standard.string(forKey: "menuBarSensorMode") ?? "maxCPU"
        return MenuBarSensorMode(rawValue: raw) ?? .maxCPU
    }() {
        didSet { UserDefaults.standard.set(menuBarSensorMode.rawValue, forKey: "menuBarSensorMode") }
    }
    @Published var menuBarSensorKey: String = UserDefaults.standard.string(forKey: "menuBarSensorKey") ?? "" {
        didSet { UserDefaults.standard.set(menuBarSensorKey, forKey: "menuBarSensorKey") }
    }
    @Published var activePreset: String = UserDefaults.standard.string(forKey: "activePreset") ?? "auto" {
        didSet { UserDefaults.standard.set(activePreset, forKey: "activePreset") }
    }

    /// Suppresses activePreset → "custom" when applyPreset() is changing things internally
    private var applyingPreset = false

    let smc = SMCConnection()
    let fanManager: FanManager
    let tempManager: TemperatureManager
    let curveStore = FanCurveStore()
    let helper = HelperClient()

    private var refreshTimer: Timer?

    func formatTemp(_ celsius: Double) -> String {
        if useFahrenheit {
            let f = celsius * 9.0 / 5.0 + 32.0
            return "\(Int(f.rounded()))°F"
        }
        return "\(Int(celsius.rounded()))°C"
    }

    var maxCPUTemp: Double? {
        let cpuSensors = temperatures.filter {
            $0.key.hasPrefix("TC") || $0.key.hasPrefix("Tp")
        }
        guard !cpuSensors.isEmpty else { return nil }
        return cpuSensors.map(\.temperature).max()
    }

    var menuBarTemperature: Double? {
        switch menuBarSensorMode {
        case .none:
            return nil
        case .maxCPU:
            return maxCPUTemp
        case .specific:
            return temperatures.first(where: { $0.key == menuBarSensorKey })?.temperature
        }
    }

    init() {
        self.fanManager = FanManager(smc: smc)
        self.tempManager = TemperatureManager(smc: smc)

        do {
            try smc.open()
        } catch {
            lastError = "Cannot open SMC: \(error.localizedDescription)"
        }

        // Check if helper daemon is available
        helperConnected = helper.ping()

        // Restore persisted state
        curves = curveStore.load()
        loadManualState()
        refresh()

        // Re-apply the saved preset (or manual state if "custom")
        if activePreset != "custom" {
            applyPreset(activePreset)
        } else {
            reapplyManualState()
        }
        startMonitoring()

        // Restore fans to auto mode on app termination
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreAutoMode()
        }

        // Prompt to install helper if not connected
        if !helperConnected {
            promptHelperInstall()
        }
    }

    func promptHelperInstall() {
        guard HelperInstaller.shared.isBundled else { return }

        Task { @MainActor in
            // Small delay so the app UI has time to appear
            try? await Task.sleep(for: .seconds(1))
            await installHelper()
        }
    }

    func installHelper() async {
        helperInstalling = true
        defer { helperInstalling = false }

        // Run the install on a background thread (it blocks waiting for the auth dialog)
        let result: String? = await Task.detached {
            await HelperInstaller.shared.install()
        }.value

        if let error = result {
            if error == "cancelled" {
                // User cancelled, don't nag
                return
            }
            lastError = "Helper install failed: \(error)"
            return
        }

        // Wait a moment for the daemon to start
        try? await Task.sleep(for: .seconds(1))

        // Re-check connection
        helperConnected = helper.ping()
        if helperConnected {
            lastError = nil
        } else {
            lastError = "Helper installed but not responding. Check /var/log/fancontrol-helper.log"
        }
    }

    nonisolated func restoreAutoMode() {
        if helper.isAvailable {
            _ = helper.setAllAuto()
        } else {
            try? fanManager.setAllAutoMode()
        }
    }

    // MARK: - Persistence for manual fan state

    private func saveManualState() {
        // Convert [Int: Double] to [String: Double] for UserDefaults
        let speedsDict = Dictionary(uniqueKeysWithValues: manualSpeeds.map { (String($0.key), $0.value) })
        let enabledDict = Dictionary(uniqueKeysWithValues: manualEnabled.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(speedsDict, forKey: "manualSpeeds")
        UserDefaults.standard.set(enabledDict, forKey: "manualEnabled")
    }

    private func loadManualState() {
        if let speedsDict = UserDefaults.standard.dictionary(forKey: "manualSpeeds") as? [String: Double] {
            manualSpeeds = Dictionary(uniqueKeysWithValues: speedsDict.compactMap { key, val in
                Int(key).map { ($0, val) }
            })
        }
        if let enabledDict = UserDefaults.standard.dictionary(forKey: "manualEnabled") as? [String: Bool] {
            manualEnabled = Dictionary(uniqueKeysWithValues: enabledDict.compactMap { key, val in
                Int(key).map { ($0, val) }
            })
        }
    }

    private func reapplyManualState() {
        for (index, enabled) in manualEnabled where enabled {
            if let speed = manualSpeeds[index] {
                _ = writeFanSpeed(index: index, percentage: speed)
            }
        }
    }

    func startMonitoring() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.applyCurves()
            }
        }
    }

    func refresh() {
        fans = (try? fanManager.getAllFans()) ?? []
        temperatures = (try? tempManager.readTemperatures()) ?? []
    }

    // MARK: - Fan Control (tries helper first, falls back to direct SMC)

    private func writeFanSpeed(index: Int, percentage: Double) -> Bool {
        // Try helper daemon first
        if helper.isAvailable {
            let response = helper.setFanSpeed(index: index, percentage: percentage)
            if response.success {
                helperConnected = true
                return true
            }
        }

        // Fall back to direct SMC write (requires running as root)
        do {
            try fanManager.setFanSpeed(index: index, percentage: percentage)
            isPrivileged = true
            return true
        } catch {
            return false
        }
    }

    private func writeFanAuto(index: Int) -> Bool {
        if helper.isAvailable {
            let response = helper.setFanMode(index: index, manual: false)
            if response.success {
                helperConnected = true
                return true
            }
        }

        do {
            try fanManager.setAutoMode(index: index)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Presets

    func applyPreset(_ preset: String) {
        applyingPreset = true
        defer { applyingPreset = false }

        activePreset = preset

        switch preset {
        case "auto":
            // Disable all manual modes
            manualEnabled = [:]
            manualSpeeds = [:]
            saveManualState()
            // Disable all curves
            for i in curves.indices { curves[i].enabled = false }
            curveStore.save(curves)
            // Set all fans to auto
            for fan in fans { _ = writeFanAuto(index: fan.index) }

        case "fullBlast":
            // Disable all curves
            for i in curves.indices { curves[i].enabled = false }
            curveStore.save(curves)
            // Set all fans to 100%
            for fan in fans {
                manualSpeeds[fan.index] = 100
                manualEnabled[fan.index] = true
                _ = writeFanSpeed(index: fan.index, percentage: 100)
            }
            saveManualState()

        default:
            // Treat as a curve UUID — enable that curve, disable others
            for i in curves.indices {
                curves[i].enabled = (curves[i].id.uuidString == preset)
            }
            curveStore.save(curves)
            // Clear manual modes so the curve can drive fans
            manualEnabled = [:]
            manualSpeeds = [:]
            saveManualState()
            // Set all fans to auto first, then applyCurves() will take over
            for fan in fans { _ = writeFanAuto(index: fan.index) }
            applyCurves()
        }
    }

    func setFanSpeed(index: Int, percentage: Double) {
        manualSpeeds[index] = percentage
        manualEnabled[index] = true
        saveManualState()

        if writeFanSpeed(index: index, percentage: percentage) {
            lastError = nil
        } else {
            lastError = "Fan control requires the helper daemon."
            manualEnabled[index] = false
            saveManualState()
        }

        if !applyingPreset { activePreset = "custom" }
    }

    func setAutoMode(index: Int) {
        manualEnabled[index] = false
        manualSpeeds.removeValue(forKey: index)
        saveManualState()

        if !writeFanAuto(index: index) {
            lastError = "Failed to set auto mode"
        }

        if !applyingPreset { activePreset = "custom" }
    }

    func addCurve(_ curve: FanCurveConfig) {
        curves.append(curve)
        curveStore.save(curves)
    }

    func updateCurve(_ curve: FanCurveConfig) {
        if let idx = curves.firstIndex(where: { $0.id == curve.id }) {
            curves[idx] = curve
            curveStore.save(curves)
        }
    }

    func deleteCurve(_ curve: FanCurveConfig) {
        curves.removeAll { $0.id == curve.id }
        curveStore.save(curves)
    }

    func toggleCurve(_ curve: FanCurveConfig) {
        if let idx = curves.firstIndex(where: { $0.id == curve.id }) {
            curves[idx].enabled.toggle()
            curveStore.save(curves)

            // If disabling, restore auto mode for affected fans (unless another curve or manual controls them)
            if !curves[idx].enabled {
                for fanIdx in curves[idx].fanIndices {
                    if manualEnabled[fanIdx] == true { continue }
                    let otherCurveControlsFan = curves.contains { $0.enabled && $0.id != curves[idx].id && $0.fanIndices.contains(fanIdx) }
                    if !otherCurveControlsFan {
                        _ = writeFanAuto(index: fanIdx)
                    }
                }
            }

            if !applyingPreset { activePreset = "custom" }
        }
    }

    /// Apply all enabled curves. For each fan, the highest commanded speed wins.
    /// Manual mode always takes precedence over curves.
    private func applyCurves() {
        // Collect the max commanded speed per fan across all enabled curves
        var fanTargets: [Int: Double] = [:]

        for curve in curves where curve.enabled {
            guard let temp = try? tempManager.readTemperature(curve.temperatureSensorKey) else { continue }
            let targetPercent = curve.interpolate(temperature: temp)

            for fanIndex in curve.fanIndices {
                // Manual mode takes absolute precedence
                if manualEnabled[fanIndex] == true { continue }

                // Highest speed wins across all curves
                if let existing = fanTargets[fanIndex] {
                    fanTargets[fanIndex] = max(existing, targetPercent)
                } else {
                    fanTargets[fanIndex] = targetPercent
                }
            }
        }

        // Apply the resolved targets
        for (fanIndex, targetPercent) in fanTargets {
            _ = writeFanSpeed(index: fanIndex, percentage: targetPercent)
        }
    }

    deinit {
        refreshTimer?.invalidate()
        restoreAutoMode()
        smc.close()
    }
}
