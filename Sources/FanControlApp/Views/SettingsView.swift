import SwiftUI
import SMCKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Temperature") {
                Picker("Unit", selection: $state.useFahrenheit) {
                    Text("Celsius (°C)").tag(false)
                    Text("Fahrenheit (°F)").tag(true)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Menu Bar Display") {
                Picker("Show Temperature", selection: $state.menuBarSensorMode) {
                    Text("None (icon only)").tag(MenuBarSensorMode.none)
                    Text("Max CPU Temperature").tag(MenuBarSensorMode.maxCPU)
                    Text("Specific Sensor").tag(MenuBarSensorMode.specific)
                }
                .pickerStyle(.radioGroup)

                if state.menuBarSensorMode == .specific {
                    Picker("Sensor", selection: $state.menuBarSensorKey) {
                        ForEach(state.temperatures.filter { $0.temperature > 5.0 }) { sensor in
                            Text("\(sensor.name) — \(state.formatTemp(sensor.temperature))")
                                .tag(sensor.key)
                        }
                    }
                }
            }

            Section("Behavior") {
                Toggle("Reset fans to auto on sleep", isOn: $state.resetOnSleep)
                Text("When enabled, fans return to macOS automatic control when your Mac sleeps and your preset is re-applied on wake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Helper Daemon") {
                HStack {
                    Text("Status")
                    Spacer()
                    if state.helperInstalling {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing...")
                            .foregroundStyle(.secondary)
                    } else if state.helperConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not installed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if !state.helperConnected && !state.helperInstalling {
                    Text("Fan speed control requires a privileged helper daemon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await state.installHelper() }
                    } label: {
                        Label("Install Helper Daemon", systemImage: "lock.shield")
                    }
                    .controlSize(.small)
                }

                if state.helperConnected {
                    Button {
                        Task { await state.installHelper() }
                    } label: {
                        Label("Reinstall Helper", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                HStack {
                    Text("FanControl")
                    Spacer()
                    Text("v1.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Fans detected")
                    Spacer()
                    Text("\(state.fans.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Temperature sensors")
                    Spacer()
                    Text("\(state.temperatures.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
