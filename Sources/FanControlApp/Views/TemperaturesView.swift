import SwiftUI
import SMCKit

struct TemperaturesView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText = ""
    @State private var showAll = false

    private var filteredSensors: [TemperatureSensor] {
        var sensors = state.temperatures
        if !showAll {
            sensors = sensors.filter { $0.temperature > 5.0 }
        }
        if !searchText.isEmpty {
            sensors = sensors.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return sensors
    }

    private var groupedSensors: [(String, [TemperatureSensor])] {
        let sensors = filteredSensors
        var groups: [(String, [TemperatureSensor])] = []

        let categories: [(String, (TemperatureSensor) -> Bool)] = [
            ("CPU", { $0.key.hasPrefix("TC") || $0.key.hasPrefix("Tp") }),
            ("GPU", { $0.key.hasPrefix("Tg") || $0.key.hasPrefix("TG") }),
            ("Memory", { $0.key.hasPrefix("Tm") }),
            ("Battery", { $0.key.hasPrefix("TB") }),
            ("Storage", { $0.key.hasPrefix("TH") || $0.key.hasPrefix("TD") }),
            ("Power", { $0.key.hasPrefix("TP") }),
            ("Thermal", { $0.key.hasPrefix("Td") || $0.key.hasPrefix("Th") || $0.key.hasPrefix("Ts") || $0.key.hasPrefix("Te") }),
            ("Other", { _ in true }),
        ]

        var remaining = sensors
        for (name, predicate) in categories {
            let matched = remaining.filter(predicate)
            if !matched.isEmpty {
                groups.append((name, matched))
                remaining.removeAll { s in matched.contains(where: { $0.key == s.key }) }
            }
        }

        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search sensors...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Toggle("All", isOn: $showAll)
                    .controlSize(.small)
                    .help("Show sensors reading < 5°C")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                    ForEach(groupedSensors, id: \.0) { group in
                        Section {
                            ForEach(group.1) { sensor in
                                SensorRow(sensor: sensor)
                            }
                        } header: {
                            Text(group.0)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            HStack {
                Text("\(filteredSensors.count) sensors")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let maxTemp = state.maxCPUTemp {
                    Text("Peak CPU: \(state.formatTemp(maxTemp))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}

struct SensorRow: View {
    @EnvironmentObject var state: AppState
    let sensor: TemperatureSensor

    var body: some View {
        HStack {
            Text(sensor.key)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 45, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(sensor.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(state.formatTemp(sensor.temperature))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(tempColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var tempColor: Color {
        let t = sensor.temperature
        if t < 40 { return .green }
        if t < 60 { return .primary }
        if t < 80 { return .orange }
        return .red
    }
}
