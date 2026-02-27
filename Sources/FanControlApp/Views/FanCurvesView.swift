import SwiftUI
import SMCKit
import Charts

struct FanCurvesView: View {
    @EnvironmentObject var state: AppState
    @State private var showEditor = false
    @State private var editingCurve: FanCurveConfig?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if state.curves.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No Fan Curves")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Create a curve to automatically adjust fan speed based on temperature.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ForEach(state.curves) { curve in
                        CurveCard(curve: curve) {
                            editingCurve = curve
                            showEditor = true
                        }
                    }
                }

                Button {
                    editingCurve = nil
                    showEditor = true
                } label: {
                    Label("New Curve", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        }
        .sheet(isPresented: $showEditor) {
            FanCurveEditorView(
                existingCurve: editingCurve,
                availableSensors: state.temperatures.filter { $0.temperature > 5.0 },
                fanCount: state.fans.count
            ) { curve in
                if editingCurve != nil {
                    state.updateCurve(curve)
                } else {
                    state.addCurve(curve)
                }
            }
            .environmentObject(state)
        }
    }
}

struct CurveCard: View {
    @EnvironmentObject var state: AppState
    let curve: FanCurveConfig
    let onEdit: () -> Void

    private var sensorTemp: Double? {
        state.temperatures.first(where: { $0.key == curve.temperatureSensorKey })?.temperature
    }

    private var sensorName: String {
        state.temperatures.first(where: { $0.key == curve.temperatureSensorKey })?.name ?? curve.temperatureSensorKey
    }

    private func displayTemp(_ celsius: Double) -> Double {
        state.useFahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: Binding(
                    get: { curve.enabled },
                    set: { _ in state.toggleCurve(curve) }
                )) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Text(curve.name)
                    .font(.headline)
                    .lineLimit(1)

                if curve.limitMode != nil {
                    Text("LIMIT")
                        .font(.system(.caption2, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button(role: .destructive) {
                    state.deleteCurve(curve)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Label(sensorName, systemImage: "thermometer.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let temp = sensorTemp {
                    Text(state.formatTemp(temp))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let limit = curve.limitMode {
                    Text("Max: \(state.formatTemp(limit.maxTemperature))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
                Label("Fan \(curve.fanIndices.map(String.init).joined(separator: ","))", systemImage: "fan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Mini curve chart
            if !curve.points.isEmpty {
                let displayPoints = curve.points.map { displayTemp($0.temperature) }
                let allTemps = displayPoints + (sensorTemp.map { [displayTemp($0)] } ?? [])
                let xMin = (allTemps.min() ?? 0) - 2
                let xMax = (allTemps.max() ?? 100) + 2

                Chart {
                    ForEach(curve.points.sorted(by: { $0.temperature < $1.temperature })) { point in
                        LineMark(
                            x: .value("Temp", displayTemp(point.temperature)),
                            y: .value("Speed", point.fanSpeedPercent)
                        )
                        .foregroundStyle(curve.enabled ? .blue : .gray)
                        PointMark(
                            x: .value("Temp", displayTemp(point.temperature)),
                            y: .value("Speed", point.fanSpeedPercent)
                        )
                        .foregroundStyle(curve.enabled ? .blue : .gray)
                    }

                    // Current temperature marker
                    if let temp = sensorTemp {
                        let speed = curve.interpolate(temperature: temp)
                        RuleMark(x: .value("Current", displayTemp(temp)))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [4, 4]))
                        PointMark(
                            x: .value("Temp", displayTemp(temp)),
                            y: .value("Speed", speed)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(50)
                    }
                }
                .chartXScale(domain: xMin...xMax)
                .chartYScale(domain: 0...100)
                .chartXAxisLabel(state.useFahrenheit ? "°F" : "°C")
                .chartYAxisLabel("%")
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100])
                }
                .frame(height: 120)
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(curve.enabled ? 1.0 : 0.6)
    }
}

struct FanCurveEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var state: AppState

    let existingCurve: FanCurveConfig?
    let availableSensors: [TemperatureSensor]
    let fanCount: Int
    let onSave: (FanCurveConfig) -> Void

    @State private var name: String = ""
    @State private var selectedSensor: String = ""
    @State private var selectedFans: Set<Int> = [0]
    @State private var points: [FanCurvePoint] = [
        FanCurvePoint(temperature: 40, fanSpeedPercent: 20),
        FanCurvePoint(temperature: 60, fanSpeedPercent: 50),
        FanCurvePoint(temperature: 80, fanSpeedPercent: 100),
    ]
    @State private var isLimitMode: Bool = false
    @State private var comfortTemp: Double = 35
    @State private var maxTemp: Double = 50

    init(existingCurve: FanCurveConfig?, availableSensors: [TemperatureSensor], fanCount: Int, onSave: @escaping (FanCurveConfig) -> Void) {
        self.existingCurve = existingCurve
        self.availableSensors = availableSensors
        self.fanCount = fanCount
        self.onSave = onSave
    }

    private var useFahrenheit: Bool { state.useFahrenheit }
    private var unitLabel: String { useFahrenheit ? "°F" : "°C" }

    private func toDisplay(_ celsius: Double) -> Double {
        useFahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
    }

    private func toCelsius(_ display: Double) -> Double {
        useFahrenheit ? (display - 32.0) * 5.0 / 9.0 : display
    }

    private func updateLimitPoints() {
        if isLimitMode {
            let comfortC = toCelsius(comfortTemp)
            let maxC = toCelsius(maxTemp)
            let limit = TemperatureLimitMode(comfortTemperature: comfortC, maxTemperature: maxC)
            points = limit.generatePoints()
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(existingCurve == nil ? "New Fan Curve" : "Edit Fan Curve")
                .font(.headline)

            Form {
                // Curve type toggle
                Picker("Curve Type", selection: $isLimitMode) {
                    Text("Custom Curve").tag(false)
                    Text("Temperature Limit").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: isLimitMode) { _, newValue in
                    if newValue { updateLimitPoints() }
                }

                TextField("Name", text: $name)

                Picker("Temperature Sensor", selection: $selectedSensor) {
                    ForEach(availableSensors) { sensor in
                        Text("\(sensor.name) (\(sensor.key))")
                            .tag(sensor.key)
                    }
                }

                Section("Fans to Control") {
                    ForEach(0..<fanCount, id: \.self) { i in
                        Toggle("Fan \(i)", isOn: Binding(
                            get: { selectedFans.contains(i) },
                            set: { on in
                                if on { selectedFans.insert(i) }
                                else { selectedFans.remove(i) }
                            }
                        ))
                    }
                }

                if isLimitMode {
                    Section("Temperature Limit") {
                        HStack {
                            Text("Comfort")
                            Spacer()
                            TextField("", value: $comfortTemp, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: comfortTemp) { _, _ in updateLimitPoints() }
                            Text(unitLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Maximum")
                            Spacer()
                            TextField("", value: $maxTemp, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: maxTemp) { _, _ in updateLimitPoints() }
                            Text(unitLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Fans stay quiet below the comfort temperature and ramp to 100% at the maximum.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Curve Points") {
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            HStack {
                                Text("Temp:")
                                    .font(.caption)
                                TextField(unitLabel, value: Binding(
                                    get: { toDisplay(points[index].temperature) },
                                    set: { points[index].temperature = toCelsius($0) }
                                ), format: .number.precision(.fractionLength(0)))
                                .frame(width: 55)
                                .textFieldStyle(.roundedBorder)

                                Text(unitLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Speed:")
                                    .font(.caption)
                                TextField("%", value: Binding(
                                    get: { points[index].fanSpeedPercent },
                                    set: { points[index].fanSpeedPercent = max(0, min(100, $0)) }
                                ), format: .number.precision(.fractionLength(0)))
                                .frame(width: 50)
                                .textFieldStyle(.roundedBorder)

                                Text("%")
                                    .font(.caption)

                                Spacer()

                                if points.count > 2 {
                                    Button(role: .destructive) {
                                        points.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Button {
                            let lastDisplayTemp = toDisplay(points.last?.temperature ?? 80)
                            let newDisplayTemp = lastDisplayTemp + (useFahrenheit ? 15 : 10)
                            points.append(FanCurvePoint(temperature: toCelsius(newDisplayTemp), fanSpeedPercent: 100))
                        } label: {
                            Label("Add Point", systemImage: "plus")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            // Preview chart
            if !points.isEmpty {
                let displayTemps = points.map { toDisplay($0.temperature) }
                let editorXMin = (displayTemps.min() ?? 0) - 2
                let editorXMax = (displayTemps.max() ?? 100) + 2

                Chart {
                    ForEach(points.sorted(by: { $0.temperature < $1.temperature })) { point in
                        LineMark(
                            x: .value("Temp", toDisplay(point.temperature)),
                            y: .value("Speed", point.fanSpeedPercent)
                        )
                        PointMark(
                            x: .value("Temp", toDisplay(point.temperature)),
                            y: .value("Speed", point.fanSpeedPercent)
                        )
                    }
                }
                .chartXScale(domain: editorXMin...editorXMax)
                .chartYScale(domain: 0...100)
                .chartXAxisLabel("Temperature (\(unitLabel))")
                .chartYAxisLabel("Fan Speed (%)")
                .frame(height: 100)
                .padding(.horizontal)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var curve = existingCurve ?? FanCurveConfig(
                        name: name,
                        temperatureSensorKey: selectedSensor,
                        fanIndices: Array(selectedFans).sorted(),
                        points: points
                    )
                    if existingCurve != nil {
                        curve.name = name
                        curve.temperatureSensorKey = selectedSensor
                        curve.fanIndices = Array(selectedFans).sorted()
                        curve.points = points
                    }
                    if isLimitMode {
                        let comfortC = toCelsius(comfortTemp)
                        let maxC = toCelsius(maxTemp)
                        curve.limitMode = TemperatureLimitMode(comfortTemperature: comfortC, maxTemperature: maxC)
                        curve.regeneratePointsIfNeeded()
                    } else {
                        curve.limitMode = nil
                    }
                    onSave(curve)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || selectedSensor.isEmpty || selectedFans.isEmpty || (isLimitMode && comfortTemp >= maxTemp))
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .onAppear {
            if let curve = existingCurve {
                name = curve.name
                selectedSensor = curve.temperatureSensorKey
                selectedFans = Set(curve.fanIndices)
                points = curve.points
                if let limit = curve.limitMode {
                    isLimitMode = true
                    comfortTemp = toDisplay(limit.comfortTemperature)
                    maxTemp = toDisplay(limit.maxTemperature)
                }
            } else if let first = availableSensors.first(where: { $0.key.hasPrefix("TC") }) ?? availableSensors.first {
                selectedSensor = first.key
            }
        }
    }
}
