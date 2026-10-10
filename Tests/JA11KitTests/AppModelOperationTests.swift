import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

/// A model on a `FakeDongle` with a backup store in a fresh temporary directory. Nothing here can
/// reach the real dongle or the real backup file.
@MainActor
struct OperationFixture {
    let model: AppModel
    let dongle: FakeDongle
    let store: BackupStore
    let directory: URL

    /// Builds the model, starts it and (by default) waits until the editor is loaded.
    static func with(
        dongle: FakeDongle = FakeDongle(),
        connected: Bool = true,
        _ body: @MainActor (OperationFixture) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ja11-app-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(fileURL: directory.appendingPathComponent("user1-original.json"))
        let device = try await ApplyTests.makeDevice(on: dongle, connected: false)
        let model = AppModel(
            device: device,
            writer: JA11Writer(device: device, store: store),
            sampleRates: NilSampleRates()
        )
        model.start()
        if connected {
            dongle.transport.emit(.connected)
            await waitUntil("editor loaded") { model.deviceState != nil }
        }
        let fixture = OperationFixture(model: model, dongle: dongle, store: store, directory: directory)
        do {
            try await body(fixture)
        } catch {
            model.stop()
            throw error
        }
        model.stop()
    }

    /// Writes `text` where the backup file would be.
    func plantBackupFile(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: store.fileURL)
    }
}

@MainActor
@Suite struct AppModelOperationTests {
    @Test func confirmedApplySendsNineFramesAndMarksTheEditorClean() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            #expect(f.model.editor.isDirty)
            #expect(f.model.canApply)

            await f.model.apply()

            #expect(f.dongle.writeFrames.count == 9)
            #expect(f.dongle.user1.bands[1].gain == -3.0)
            #expect(f.model.outcome == .confirmed("Applied and confirmed"))
            #expect(!f.model.editor.isDirty)
            #expect(f.model.operation == .idle)
            #expect(f.model.deviceState == f.dongle.state)
            #expect(f.store.exists)
        }
    }

    @Test func secondApplyAfterAConfirmedOneSendsNothingUntilTheNextEdit() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()
            #expect(f.dongle.writeFrames.count == 9)

            #expect(!f.model.canApply)
            await f.model.apply()
            #expect(f.dongle.writeFrames.count == 9)

            f.model.editor.setGain(2, band: 2)
            #expect(f.model.canApply)
            await f.model.apply()
            #expect(f.dongle.writeFrames.count == 18)
            #expect(f.model.outcome == .confirmed("Applied and confirmed"))
        }
    }

    @Test func doublePressSendsOneSequence() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            async let first: Void = f.model.apply()
            async let second: Void = f.model.apply()
            _ = await (first, second)

            #expect(f.dongle.writeFrames.count == 9)
            #expect(f.model.outcome == .confirmed("Applied and confirmed"))
        }
    }

    @Test func mismatchIsReportedAndTheEditorStaysDirty() async throws {
        try await OperationFixture.with(dongle: FakeDongle(gainError: (index: 1, tenths: 1))) { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()

            #expect(f.model.outcome == .mismatch(["filter 1 gain: sent -3.0 dB, read -2.9 dB"]))
            #expect(f.model.editor.isDirty)
            #expect(f.model.visibleOutcome?.isSuccess == false)
            #expect(f.model.canApply)
            #expect(f.model.operation == .idle)
        }
    }

    @Test func ignoredWritesGiveAMismatchWithSeveralLines() async throws {
        try await OperationFixture.with(dongle: FakeDongle(ignoresWrites: true)) { f in
            f.model.editor.setGain(-3, band: 1)
            f.model.editor.setGain(4, band: 3)
            await f.model.apply()

            guard case .mismatch(let lines) = f.model.outcome else {
                Issue.record("expected a mismatch, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(lines.count > 1)
            #expect(f.model.editor.isDirty)
        }
    }

    @Test func aDongleThatNeverReturnsGivesNoReadBackAndThenNotConnected() async throws {
        try await OperationFixture.with(dongle: FakeDongle(afterSave: .dropsForGood)) { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()

            guard case .failed(let text) = f.model.outcome else {
                Issue.record("expected a failure, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(text.hasPrefix("No read-back"))
            #expect(f.model.editor.isDirty)
            await waitUntil("not connected shown") { f.model.connection == .notConnected }
            #expect(f.model.connection == .notConnected)
        }
    }

    @Test func theDropAfterTheSaveIsNeverShownAsNotConnected() async throws {
        try await OperationFixture.with(dongle: FakeDongle(afterSave: .dropsAndReturns(after: .milliseconds(100)))) { f in
            let model = f.model
            var sampling = true
            var sawNotConnected = false
            var sawApplying = false
            var busyFlagsOK = true
            let sampler = Task { @MainActor in
                while sampling {
                    if model.connection != .connected { sawNotConnected = true }
                    if model.operation == .applying {
                        sawApplying = true
                        if model.canRevert || model.canSelectPreset || model.canRestore || model.editorEnabled
                            || model.canApply {
                            busyFlagsOK = false
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(1))
                }
            }

            model.editor.setGain(-3, band: 1)
            let sent = model.editor.curve
            await model.apply()
            // Let the returned dongle's state arrive and be ignored or taken.
            try? await Task.sleep(for: .milliseconds(100))
            sampling = false
            await sampler.value

            #expect(model.outcome == .confirmed("Applied and confirmed"))
            #expect(!sawNotConnected)
            #expect(sawApplying)
            #expect(busyFlagsOK)
            #expect(!model.editor.isDirty)
            #expect(model.editor.curve == sent)
            #expect(model.operation == .idle)
            #expect(model.connection == .connected)
        }
    }

    @Test func applyIsRefusedWhereTheDecisionsSayAndSendsNothing() async throws {
        // Clean editor.
        try await OperationFixture.with { f in
            #expect(!f.model.canApply)
            await f.model.apply()
            #expect(f.dongle.writeFrames.isEmpty)
            #expect(f.model.outcome == nil)
        }
        // Factory slot active.
        try await OperationFixture.with(dongle: FakeDongle(slot: 0)) { f in
            f.model.editor.setGain(-3, band: 1)
            #expect(!f.model.canApply)
            await f.model.apply()
            #expect(f.dongle.writeFrames.isEmpty)
        }
        // Never connected.
        try await OperationFixture.with(connected: false) { f in
            #expect(!f.model.canApply)
            await f.model.apply()
            #expect(f.dongle.transport.sent.isEmpty)
        }
    }

    @Test func aStateArrivingAfterTheApplyNeverOverwritesAnEdit() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()
            let applied = f.model.editor.curve

            // Clean editor: the arriving state equals what was applied.
            f.model.handle(.state(f.dongle.state))
            #expect(f.model.editor.curve == applied)
            #expect(!f.model.editor.isDirty)

            // Pending edit: not overwritten.
            f.model.editor.setGain(5, band: 4)
            let edited = f.model.editor.curve
            f.model.handle(.state(f.dongle.state))
            #expect(f.model.editor.curve == edited)
            #expect(f.model.editor.isDirty)
        }
    }

    @Test func visibleOutcomeHidesConfirmationOnceTheEditorIsDirtyAgain() async throws {
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()
            #expect(f.model.visibleOutcome == .confirmed("Applied and confirmed"))
            f.model.editor.setGain(1, band: 0)
            #expect(f.model.visibleOutcome == nil)
        }
        try await OperationFixture.with(dongle: FakeDongle(ignoresWrites: true)) { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()
            f.model.editor.setGain(1, band: 0)
            #expect(f.model.visibleOutcome != nil)
        }
    }

    @Test func anUnreadableBackupEndsTheApplyBeforeAnythingIsSent() async throws {
        try await OperationFixture.with { f in
            try f.plantBackupFile("not json")
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()

            guard case .failed(let text) = f.model.outcome else {
                Issue.record("expected a failure, got \(String(describing: f.model.outcome))")
                return
            }
            #expect(text.contains("cannot be read"))
            #expect(f.dongle.writeFrames.isEmpty)
            #expect(f.model.editor.isDirty)
        }
    }

    @Test func anOperationStartedDuringAConnectWaitsForTheWatchLoopsRead() async throws {
        try await OperationFixture.with { f in
            let readsBefore = f.dongle.transport.sent.count
            f.dongle.transport.emit(.disconnected)
            f.dongle.transport.emit(.connected)
            f.model.editor.setGain(-3, band: 1)
            await waitUntil("reconnected") { f.model.connection == .connected }

            await f.model.apply()

            #expect(f.model.outcome == .confirmed("Applied and confirmed"))
            let sent = f.dongle.transport.sent
            let firstWrite = try #require(sent.firstIndex { $0.starts(with: [0xAA, 0x0A]) })
            #expect(firstWrite - readsBefore >= 8)
        }
    }

    @Test func theAppSendsNothingToTheRealBackupFile() async throws {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JA11 EQ/user1-original.json")
        let before = try? FileManager.default.attributesOfItem(atPath: real.path)[.modificationDate] as? Date
        try await OperationFixture.with { f in
            f.model.editor.setGain(-3, band: 1)
            await f.model.apply()
            #expect(f.store.fileURL != real)
        }
        let after = try? FileManager.default.attributesOfItem(atPath: real.path)[.modificationDate] as? Date
        #expect(before == after)
    }
}
