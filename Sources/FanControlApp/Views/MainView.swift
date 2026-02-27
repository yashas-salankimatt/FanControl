import SwiftUI
import SMCKit

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "fan.fill")
                    .symbolEffect(.variableColor, isActive: state.fans.contains { $0.currentRPM > 1600 })
                Text("FanControl")
                    .font(.headline)
                Spacer()
                if state.helperConnected {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .help("Helper daemon connected — fan control active")
                } else if state.isPrivileged {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(.green)
                        .help("Running with root privileges")
                } else {
                    Image(systemName: "shield.slash")
                        .foregroundStyle(.secondary)
                        .help("Helper not installed — fan control disabled. Run install-helper.sh")
                }
                if let error = state.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Preset dropdown
            HStack {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { state.activePreset },
                    set: { state.applyPreset($0) }
                )) {
                    Text("Auto (macOS)").tag("auto")
                    Text("Full Blast").tag("fullBlast")
                    if !state.curves.isEmpty {
                        Divider()
                        ForEach(state.curves) { curve in
                            Text(curve.name).tag(curve.id.uuidString)
                        }
                    }
                    if state.activePreset == "custom" {
                        Divider()
                        Text("Custom").tag("custom")
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Fans").tag(0)
                Text("Temps").tag(1)
                Text("Curves").tag(2)
                Text("Settings").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Content
            switch selectedTab {
            case 0:
                FansView()
            case 1:
                TemperaturesView()
            case 2:
                FanCurvesView()
            case 3:
                SettingsView()
            default:
                EmptyView()
            }
        }
        .frame(width: 420, height: 520)
    }
}
