import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

/// Preset switching, Revert and Restore on a `FakeDongle` with a temporary backup store.
@MainActor
@Suite struct AppModelPresetTests {
    private static var originalCurve: EQCurve {
        EQCurve(state: EQState(slotID: 3, preGain: 0.0, bands: FakeDongle.originalBands))!
    }

    private static func readRequests(_ dongle: FakeDongle) -> Int {
        dongle.transport.sent.filter(FiioFrame.isGetRequest).count
    }

    @Test func switchingToBassSendsOneSelectFrameAndLoadsTheFactoryBandsReadOnly() async throws {
        try await OperationFixture.with { f in
            let store = f.store
            let existedAtSelect = LockedFlag()
            f.dongle.onWrite = { frame in
                if frame == ApplyTests.selectFrame(2) { existedAtSelect.set(store.exists) }
            }

            await f.model.selectPreset(.bass)

            #expect(f.dongle.writeFrames == [ApplyTests.selectFrame(2)])
            #expect(existedAtSelect.value)
            #expect(f.model.deviceState?.slotID == 2)
            #expect(f.model.activePresetTitle == "Bass")
            #expect(f.model.editor.curve.preGain == -2.0)
            #expect(!f.model.editor.isEditable)
            #expect(f.model.editorNote != nil)
            #expect(!f.model.canApply)
            #expect(f.model.outcome == .info("Switched to Bass"))
            #expect(f.model.operation == .idle)
        }
    }

    @Test func allFivePresetsCanBeSelectedAndReadBack() async throws {
        try await OperationFixture.with { f in
            let steps: [(PresetChoice, String, UInt8)] = [
                (.vocal, "Vocal", 0), (.classic, "Classic", 1), (.bass, "Bass", 2),
                (.off, "Off", 4), (.custom, "Custom", 3),
            ]
            for (choice, title, slot) in steps {
                await f.model.selectPreset(choice)
                #expect(f.model.activePresetTitle == title)
                #expect(f.model.deviceState?.slotID == slot)
                #expect(f.model.activePreset == choice)
            }
            #expect(f.model.editor.curve == EQCurve(state: f.dongle.user1)!.clamped())
            #expect(f.model.editor.isEditable)
            #expect(!f.model.editor.isDirty)
        }
    }

    @Test func aSwitchTheDacDoesNotConfirmIsAFailureNamingTheSlotItReports() async throws {
        try await OperationFixture.with(dongle: FakeDongle(ignoresSelect: true)) { f in
            await f.model.selectPreset(.vocal)

            guard case .failed(let text) = f.model.outcome else {
                Issue.record("expected a failure, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(text.contains("Vocal"))
            #expect(text.contains("USER1"))
            #expect(f.model.activePresetTitle == "Custom")
            #expect(f.model.editor.isEditable)
            #expect(f.model.editor.curve == EQCurve(state: f.dongle.user1)!.clamped())
        }
    }

    @Test func selectionIsRefusedWhereTheDecisionsSayAndSendsNothing() async throws {
        try await OperationFixture.with { f in
            // The preset that is already active, clean editor.
            await f.model.selectPreset(.custom)
            #expect(f.dongle.writeFrames.isEmpty)
            #expect(f.model.outcome == nil)

            // During an operation.
            let model = f.model
            var enabledDuringSwitch = true
            let sampler = Task { @MainActor in
                while model.operation == .idle { try? await Task.sleep(for: .milliseconds(1)) }
                enabledDuringSwitch = model.canSelectPreset
            }
            await model.selectPreset(.bass)
            await sampler.value
            #expect(!enabledDuringSwitch)
        }
        // Disconnected.
        try await OperationFixture.with(connected: false) { f in
            #expect(!f.model.canSelectPreset)
            await f.model.selectPreset(.bass)
            #expect(f.dongle.transport.sent.isEmpty)
        }
    }

    @Test func aDirtySwitchAsksFirstAndDiscardsOnlyWhenConfirmed() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.selectPreset(.vocal)
            #expect(f.dongle.writeFrames.isEmpty)
            #expect(f.model.pendingPreset == .vocal)

            f.model.cancelPendingPreset()
            #expect(f.model.pendingPreset == nil)
            #expect(f.model.editor.isDirty)
            #expect(f.dongle.writeFrames.isEmpty)

            await f.model.selectPreset(.vocal)
            await f.model.confirmPendingPreset()
            #expect(f.model.pendingPreset == nil)
            #expect(f.model.activePresetTitle == "Vocal")
            #expect(!f.model.editor.isDirty)
            #expect(f.model.editor.curve.preGain == -2.0)
        }
    }

    @Test func aSwitchStartedRightAfterAConnectWaitsForTheRead() async throws {
        try await OperationFixture.with { f in
            let logBefore = f.model.statusLog.count
            OperationFixture.slowReads(f.dongle)
            f.dongle.transport.emit(.disconnected)
            f.dongle.transport.emit(.connected)
            await waitUntil("drop and return seen") { f.model.statusLog.count >= logBefore + 2 }

            await f.model.selectPreset(.classic)

            #expect(f.model.outcome == .info("Switched to Classic"))
            #expect(f.dongle.writeFrames == [ApplyTests.selectFrame(1)])
        }
    }

    @Test func revertReloadsFromTheDacWithoutWriting() async throws {
        try await OperationFixture.with { f in
            #expect(!f.model.canRevert)
            f.model.editor.setGain(-3, band: 1)
            #expect(f.model.canRevert)
            let reads = Self.readRequests(f.dongle)

            await f.model.revert()

            #expect(f.model.editor.curve == EQCurve(state: f.dongle.user1)!.clamped())
            #expect(!f.model.editor.isDirty)
            #expect(Self.readRequests(f.dongle) > reads)
            #expect(f.dongle.writeFrames.isEmpty)
            #expect(!f.model.canRevert)
            #expect(f.model.operation == .idle)
        }
    }

    @Test func aFailedRevertReadReturnsToTheBaselineAndSaysSo() async throws {
        try await OperationFixture.with { f in
            let baseline = f.model.editor.curve
            f.model.editor.setGain(-3, band: 1)
            f.dongle.transport.responder = { _ in [] }

            await f.model.revert()

            #expect(f.model.editor.curve == baseline)
            guard case .failed(let text) = f.model.outcome else {
                Issue.record("expected a failure, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(text.contains("reverted"))
        }
    }

    @Test func restoreAsksFirstAndTheConfirmationCanBeCancelled() async throws {
        try await OperationFixture.with { f in
            f.model.requestRestore()
            #expect(f.model.restoreConfirmationPending)
            f.model.cancelRestore()
            #expect(!f.model.restoreConfirmationPending)
            #expect(f.dongle.writeFrames.isEmpty)
        }
        try await OperationFixture.with(connected: false) { f in
            #expect(!f.model.canRestore)
            f.model.requestRestore()
            #expect(!f.model.restoreConfirmationPending)
        }
    }

    @Test func restoreOriginalPutsTheBackedUpCurveBack() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()
            #expect(f.dongle.user1.bands[1].gain == -3.0)

            f.model.editor.setGain(4, band: 2)
            f.model.requestRestore()
            await f.model.confirmRestore()

            #expect(f.dongle.user1 == EQState(slotID: 3, preGain: 0.0, bands: FakeDongle.originalBands))
            #expect(f.model.outcome == .confirmed("Original USER1 restored and confirmed"))
            #expect(f.model.editor.curve == Self.originalCurve.clamped())
            #expect(!f.model.editor.isDirty)
            #expect(!f.model.restoreConfirmationPending)
            #expect(f.model.operation == .idle)
        }
    }

    @Test func restoreWithoutABackupSendsNothingAndSaysSo() async throws {
        try await OperationFixture.with { f in
            f.model.requestRestore()
            await f.model.confirmRestore()

            guard case .failed(let text) = f.model.outcome else {
                Issue.record("expected a failure, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(text.contains("No backup"))
            #expect(f.dongle.writeFrames.isEmpty)
        }
    }

    @Test func restoreWithAnUnreadableBackupSendsNothing() async throws {
        try await OperationFixture.with { f in
            try f.plantBackupFile("not json")
            f.model.requestRestore()
            await f.model.confirmRestore()

            guard case .failed(let text) = f.model.outcome else {
                Issue.record("expected a failure, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(text.contains("cannot be read"))
            #expect(f.dongle.writeFrames.isEmpty)
        }
    }

    @Test func aRestoreTheDacDoesNotConfirmIsAMismatch() async throws {
        try await OperationFixture.with(dongle: FakeDongle(ignoresFilters: true)) { f in
            let backup = DeviceBackup(
                savedAt: Date(timeIntervalSince1970: 1_791_000_000),
                activeSlot: JA11SlotID.user1,
                curve: EQCurve(preGain: -6.0, bands: Self.originalCurve.bands.map {
                    var band = $0
                    band.gain = 3.0
                    return band
                })
            )
            _ = try f.store.saveIfAbsent(backup)

            f.model.requestRestore()
            await f.model.confirmRestore()

            guard case .mismatch(let lines) = f.model.outcome else {
                Issue.record("expected a mismatch, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(!lines.isEmpty)
            #expect(f.model.outcome?.isSuccess == false)
            #expect(f.model.operation == .idle)
        }
    }
}

/// A flag set from the dongle's write observer (another thread) and read on the main actor.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set(_ value: Bool) { lock.withLock { flag = value } }
    var value: Bool { lock.withLock { flag } }
}
