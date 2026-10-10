import JA11EQCore
import SwiftUI

/// The five presets. The entry shown is the slot the DAC reported last, never the one requested.
struct PresetPickerView: View {
    let model: AppModel

    var body: some View {
        Picker(
            "Preset",
            selection: Binding<PresetChoice?>(
                get: { model.activePreset },
                set: { choice in
                    guard let choice else { return }
                    Task { await model.selectPreset(choice) }
                }
            )
        ) {
            ForEach(PresetChoice.allCases, id: \.self) { choice in
                Text(choice.title).tag(Optional(choice))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 200)
        .disabled(!model.canSelectPreset)
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: Binding(
                get: { model.pendingPreset != nil },
                set: { if !$0 { model.cancelPendingPreset() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard and switch", role: .destructive) {
                Task { await model.confirmPendingPreset() }
            }
            Button("Cancel", role: .cancel) { model.cancelPendingPreset() }
        } message: {
            if let pending = model.pendingPreset {
                Text("Switching to \(pending.title) discards your edits to the Custom curve.")
            }
        }
    }
}
