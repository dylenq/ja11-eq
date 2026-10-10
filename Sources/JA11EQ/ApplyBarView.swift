import JA11EQCore
import SwiftUI

/// Apply, Revert, Restore original, the unsaved-changes label, progress and the plain outcome.
struct ApplyBarView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Apply") { Task { await model.apply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canApply)
                Button("Revert") { Task { await model.revert() } }
                    .disabled(!model.canRevert)
                Button("Restore original...") { model.requestRestore() }
                    .disabled(!model.canRestore)
                if model.editor.isDirty {
                    Text("Unsaved changes").foregroundStyle(.orange)
                }
                Spacer()
                if let text = model.operation.progressText {
                    ProgressView().controlSize(.small)
                    Text(text).foregroundStyle(.secondary)
                }
            }
            if let outcome = model.visibleOutcome {
                outcomeView(outcome)
            }
        }
        .confirmationDialog(
            "Restore the original Custom curve?",
            isPresented: Binding(
                get: { model.restoreConfirmationPending },
                set: { if !$0 { model.cancelRestore() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) { Task { await model.confirmRestore() } }
            Button("Cancel", role: .cancel) { model.cancelRestore() }
        } message: {
            Text("USER1 is overwritten with the contents backed up before the first write. Unsaved edits are lost.")
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: OperationOutcome) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(outcome.isSuccess ? Color.green : Color.orange)
            Text(outcome.message)
                .foregroundStyle(outcome.isSuccess ? Color.primary : Color.red)
                .textSelection(.enabled)
        }
    }
}
