import SwiftUI
import SMCKit

struct FansView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if state.fans.isEmpty {
                    ContentUnavailableView("No Fans Detected", systemImage: "fan.slash")
                } else {
                    ForEach(state.fans, id: \.index) { fan in
                        FanCardView(fan: fan)
                    }
                }
            }
            .padding()
        }
    }
}

struct FanCardView: View {
    @EnvironmentObject var state: AppState
    let fan: FanInfo

    @State private var sliderValue: Double = 50

    private var isManual: Bool {
        state.manualEnabled[fan.index] == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fan.fill")
                    .foregroundStyle(fan.currentRPM > 2000 ? .orange : .secondary)
                Text(fan.name)
                    .font(.headline)
                Spacer()
                Text("\(Int(fan.currentRPM.rounded())) RPM")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // RPM bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rpmColor)
                        .frame(width: max(0, geo.size.width * CGFloat(fan.currentPercent / 100.0)))
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(fan.minRPM)) RPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fan.currentPercent.rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fan.maxRPM)) RPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Control
            HStack {
                Toggle(isOn: Binding(
                    get: { isManual },
                    set: { newValue in
                        if newValue {
                            state.setFanSpeed(index: fan.index, percentage: sliderValue)
                        } else {
                            state.setAutoMode(index: fan.index)
                        }
                    }
                )) {
                    Text("Manual")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Slider(value: $sliderValue, in: 0...100, step: 1) {
                    Text("Speed")
                } onEditingChanged: { editing in
                    if !editing && isManual {
                        state.setFanSpeed(index: fan.index, percentage: sliderValue)
                    }
                }
                .disabled(!isManual)

                Text("\(Int(sliderValue))%")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if let saved = state.manualSpeeds[fan.index] {
                sliderValue = saved
            }
        }
        .onChange(of: state.manualSpeeds[fan.index]) { _, newValue in
            if let newValue { sliderValue = newValue }
        }
    }

    private var rpmColor: Color {
        let pct = fan.currentPercent
        if pct < 30 { return .green }
        if pct < 60 { return .yellow }
        if pct < 85 { return .orange }
        return .red
    }
}
