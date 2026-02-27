import SwiftUI
import SMCKit

@main
struct FanControlApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        // Menu bar icon with dropdown menu
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "fan.fill")
                if let temp = appState.menuBarTemperature {
                    Text("\(appState.formatTemp(temp))")
                        .monospacedDigit()
                }
            }
        }

        // Standalone window for the full UI
        Window("FanControl", id: "main") {
            MainView()
                .environmentObject(appState)
        }
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentSize)
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow

    private var presetLabel: String {
        switch appState.activePreset {
        case "auto": return "Auto"
        case "fullBlast": return "Full Blast"
        case "custom": return "Custom"
        default:
            return appState.curves.first(where: { $0.id.uuidString == appState.activePreset })?.name ?? "Custom"
        }
    }

    var body: some View {
        // Quick stats
        if !appState.fans.isEmpty {
            ForEach(appState.fans, id: \.index) { fan in
                Text("\(fan.name): \(Int(fan.currentRPM.rounded())) RPM")
            }
            Divider()
        }
        if let maxTemp = appState.maxCPUTemp {
            Text("Peak CPU: \(appState.formatTemp(maxTemp))")
        }
        if appState.menuBarSensorMode == .specific,
           let temp = appState.menuBarTemperature {
            let name = appState.temperatures.first(where: { $0.key == appState.menuBarSensorKey })?.name ?? appState.menuBarSensorKey
            Text("\(name): \(appState.formatTemp(temp))")
        }

        Divider()

        // Preset submenu
        Menu("Mode: \(presetLabel)") {
            Button {
                appState.applyPreset("auto")
            } label: {
                if appState.activePreset == "auto" {
                    Text("✓ Auto (macOS)")
                } else {
                    Text("  Auto (macOS)")
                }
            }

            Button {
                appState.applyPreset("fullBlast")
            } label: {
                if appState.activePreset == "fullBlast" {
                    Text("✓ Full Blast")
                } else {
                    Text("  Full Blast")
                }
            }

            if !appState.curves.isEmpty {
                Divider()
                ForEach(appState.curves) { curve in
                    Button {
                        appState.applyPreset(curve.id.uuidString)
                    } label: {
                        if appState.activePreset == curve.id.uuidString {
                            Text("✓ \(curve.name)")
                        } else {
                            Text("  \(curve.name)")
                        }
                    }
                }
            }
        }

        Divider()

        Button("Open FanControl...") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit FanControl") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
