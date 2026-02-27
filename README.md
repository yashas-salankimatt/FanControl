# FanControl

A native macOS menu bar app for monitoring and controlling fan speeds on Apple Silicon Macs. Built entirely in Swift with SwiftUI.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-green)

## Features

- **Real-time monitoring** of all system fans (RPM, min/max, percentage)
- **218+ temperature sensors** — CPU, GPU, battery, SSD, and more
- **Manual fan speed control** with per-fan sliders
- **Custom fan curves** — map fan speed to any temperature sensor with arbitrary control points
- **Temperature limit mode** — simplified curve: set a comfort temp and a max temp, fans ramp automatically
- **Preset system** — quickly switch between Auto, Full Blast, or any saved curve
- **Menu bar integration** — view temps and switch presets without opening the full UI
- **Configurable menu bar display** — show max CPU temp, a specific sensor, or icon only
- **Fahrenheit/Celsius toggle** — all temperatures convert seamlessly
- **Persistent state** — manual settings, curves, presets, and preferences survive app restarts
- **Sleep/wake handling** — optionally resets fans to auto on sleep and re-applies your preset on wake
- **Safe shutdown** — fans automatically return to macOS control when the app quits

## Architecture

```
FanControl/
├── Sources/
│   ├── CSMCTypes/              # C bridging header for SMC kernel structs
│   │   └── include/smc_types.h # 80-byte packed SMCParamStruct
│   ├── SMCKit/                 # Core library (no UI dependencies)
│   │   ├── SMC.swift           # IOKit SMC communication (open, close, read, write)
│   │   ├── FanManager.swift    # Fan detection and control (F{n}Ac, F{n}Mn, F{n}Mx, F{n}Tg, F{n}Md)
│   │   ├── TemperatureManager.swift  # Temperature sensor discovery and reading
│   │   ├── FanCurve.swift      # Curve model, interpolation, limit mode, JSON persistence
│   │   ├── HelperProtocol.swift # Shared wire protocol (length-prefixed JSON over Unix socket)
│   │   └── HelperClient.swift  # Client for app → helper daemon communication
│   ├── FanControlApp/          # SwiftUI menu bar app
│   │   ├── FanControlApp.swift # App entry, MenuBarExtra, Window scene
│   │   ├── AppState.swift      # Central state management, presets, persistence
│   │   ├── HelperInstaller.swift # In-app privileged helper installation via AppleScript
│   │   └── Views/
│   │       ├── MainView.swift       # Tab layout with preset dropdown
│   │       ├── FansView.swift       # Per-fan control cards with sliders
│   │       ├── TemperaturesView.swift # Temperature sensor list
│   │       ├── FanCurvesView.swift  # Curve editor with chart preview
│   │       └── SettingsView.swift   # Preferences and helper daemon management
│   ├── FanControlCLI/          # Command-line tool for scripting/debugging
│   │   └── main.swift
│   └── FanControlHelper/       # Privileged helper daemon (runs as root)
│       └── main.swift
├── Resources/
│   ├── Info.plist              # App bundle config (LSUIElement for menu bar)
│   └── com.fancontrol.helper.plist  # LaunchDaemon config
├── build.sh                    # Build script — produces FanControl.app with bundled helper
├── install-helper.sh           # Manual helper installation (alternative to in-app install)
└── uninstall-helper.sh         # Helper removal script
```

## How It Works

### SMC Communication

The app communicates with Apple's System Management Controller (SMC) via IOKit to read temperatures and control fans. On Apple Silicon Macs, the SMC uses an 80-byte `SMCParamStruct` with specific padding requirements and little-endian `flt ` (float) values for temperatures and fan speeds.

### Privileged Helper Daemon

Fan speed control requires root privileges. The app uses a LaunchDaemon-based helper that:

1. Runs as root at `/Library/PrivilegedHelperTools/FanControlHelper`
2. Listens on a Unix domain socket at `/var/run/fancontrol.sock`
3. Accepts length-prefixed JSON commands from the app
4. Performs SMC writes on behalf of the unprivileged app

The helper is bundled inside `FanControl.app/Contents/Resources/` and installed automatically on first launch via macOS's native admin password dialog.

### Fan Control Priority

When multiple control sources target the same fan:

1. **Manual mode** always takes precedence
2. **Curves** — if multiple curves target the same fan, the highest commanded speed wins
3. **Auto mode** — fans return to macOS automatic control

### Presets

The preset system provides one-click switching between:

- **Auto (macOS)** — disables all manual/curve control, returns fans to system management
- **Full Blast** — sets all fans to 100%
- **Named curves** — enables a specific curve while disabling everything else

Presets are accessible from both the main window dropdown and the menu bar submenu.

## Building

### Requirements

- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Silicon Mac

### Build

```bash
./build.sh
```

This produces `FanControl.app` with the helper daemon bundled inside.

### Run

```bash
open FanControl.app
```

On first launch, the app will prompt for your admin password to install the privileged helper daemon. This is a one-time setup — the helper persists across reboots via LaunchDaemon.

### CLI Tool

A command-line tool is also built for scripting and debugging:

```bash
# Run with sudo for full access
sudo .build/release/FanControlCLI
```

## Manual Helper Management

If you prefer manual installation:

```bash
# Install
sudo ./install-helper.sh

# Uninstall
sudo ./uninstall-helper.sh
```

Or manage from **Settings > Helper Daemon** in the app.

## Technical Notes

- All temperatures are stored internally in Celsius; conversion to Fahrenheit is display-only
- Fan curves use linear interpolation between user-defined points
- The helper daemon uses `KeepAlive` in its LaunchDaemon plist — macOS will restart it if it crashes
- The app registers for `NSApplication.willTerminateNotification` to restore fans to auto mode on quit
- Sleep/wake is handled via `NSWorkspace.willSleepNotification` and `didWakeNotification` — configurable in Settings > Behavior
- State persistence uses UserDefaults (settings, manual state) and a JSON file in `~/Library/Application Support/FanControl/` (curves)

## License

MIT
