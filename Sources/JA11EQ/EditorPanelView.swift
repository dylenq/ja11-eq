import JA11EQCore
import JA11Kit
import SwiftUI

/// Five band rows and the pre-gain control. Layout and glue only: every change goes through the
/// `CurveEditor` operations on `model.editor`, which clamp.
struct EditorPanelView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = model.editorNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<5, id: \.self) { index in
                BandRow(model: model, index: index)
            }
            Divider()
            preGainRow
        }
        .disabled(!model.editorEnabled)
    }

    private var preGainRow: some View {
        HStack(spacing: 10) {
            Text("Pre-gain")
                .frame(width: 70, alignment: .leading)
            Slider(
                value: Binding(
                    get: { model.editor.curve.preGain },
                    set: { model.editor.setPreGain($0) }
                ),
                in: -12...12,
                step: 0.1
            )
            .disabled(model.editor.autoPreGain)
            NumberField(
                value: Binding(
                    get: { model.editor.curve.preGain },
                    set: { model.editor.setPreGain($0) }
                ),
                digits: 1
            )
            .disabled(model.editor.autoPreGain)
            Text("dB").foregroundStyle(.secondary)
            Toggle("Auto", isOn: Binding(
                get: { model.editor.autoPreGain },
                set: { model.editor.setAutoPreGain($0) }
            ))
        }
    }
}

private struct BandRow: View {
    let model: AppModel
    let index: Int

    private var band: EQBand { model.editor.curve.bands[index] }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("\(index + 1)", isOn: Binding(
                get: { band.enabled },
                set: { model.editor.setEnabled($0, band: index) }
            ))
            .frame(width: 44, alignment: .leading)

            Picker("Type", selection: Binding(
                get: { band.type },
                set: { model.editor.setType($0, band: index) }
            )) {
                Text("Peak").tag(FilterType.peak)
                Text("Low shelf").tag(FilterType.lowShelf)
                Text("High shelf").tag(FilterType.highShelf)
            }
            .labelsHidden()
            .frame(width: 100)

            labelled("Hz") {
                Slider(
                    value: Binding(
                        get: { GraphGeometry.fraction(forFrequency: band.frequency) },
                        set: { model.editor.setFrequency(GraphGeometry.frequency(forFraction: $0), band: index) }
                    ),
                    in: 0...1
                )
                NumberField(
                    value: Binding(
                        get: { band.frequency },
                        set: { model.editor.setFrequency($0, band: index) }
                    ),
                    digits: 0
                )
            }
            labelled("dB") {
                Slider(
                    value: Binding(
                        get: { band.gain },
                        set: { model.editor.setGain($0, band: index) }
                    ),
                    in: -12...12,
                    step: 0.1
                )
                NumberField(
                    value: Binding(
                        get: { band.gain },
                        set: { model.editor.setGain($0, band: index) }
                    ),
                    digits: 1
                )
            }
            labelled("Q") {
                Slider(
                    value: Binding(
                        get: { band.q },
                        set: { model.editor.setQ($0, band: index) }
                    ),
                    in: 0.1...10,
                    step: 0.01
                )
                NumberField(
                    value: Binding(
                        get: { band.q },
                        set: { model.editor.setQ($0, band: index) }
                    ),
                    digits: 2
                )
            }
        }
        .opacity(band.enabled ? 1 : 0.55)
    }

    private func labelled<Content: View>(_ unit: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
            Text(unit).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
        }
    }
}

/// A numeric field that shows the editor's stored value after commit, so a rejected number
/// visibly snaps to the limit.
private struct NumberField: View {
    @Binding var value: Double
    let digits: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 64)
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: value) { _, new in if !focused { text = format(new) } }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onSubmit { commit() }
    }

    private func commit() {
        if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)) {
            value = parsed
        }
        text = format(value)
    }

    private func format(_ number: Double) -> String {
        String(format: "%.\(digits)f", number)
    }
}
