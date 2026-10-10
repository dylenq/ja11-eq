import JA11EQCore
import JA11Kit
import SwiftUI

struct ContentView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            filterList
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(model.connection.title)
                    .font(.headline)
            }
            if let detail = model.connection.detail {
                Text(detail).foregroundStyle(.secondary)
            }
            Text("Preset: \(model.activePresetTitle)")
            Text("Sample rate: \(model.sampleRateText)")
            if let failure = model.readFailure {
                Text(failure).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var filterList: some View {
        if let state = model.deviceState {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pre-gain: \(String(format: "%.1f", state.preGain)) dB")
                ForEach(state.bands, id: \.index) { band in
                    Text("\(band.index + 1). \(band.type?.displayName ?? "type-\(band.typeID)")  \(band.frequency) Hz  \(String(format: "%+.1f", band.gain)) dB  Q \(String(format: "%.2f", band.q))")
                        .monospacedDigit()
                }
            }
        }
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: .green
        case .notConnected: .gray
        case .accessRefused: .red
        }
    }
}
