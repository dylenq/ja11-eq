import Foundation
import Testing
@testable import JA11Kit

/// The public write door: backup before any write, restore, preset switching and the test curve
/// (CONTEXT D-11, D-13, D-14, D-16), on a `FakeDongle` with the backup file in a temporary
/// directory. Nothing here creates an `HIDTransport` or touches the real backup location.
@Suite struct JA11WriterTests {
    // MARK: - Helpers

    struct Fixture {
        let writer: JA11Writer
        let store: BackupStore
        let dongle: FakeDongle
    }

    /// Runs `body` with a writer on `dongle` and a store in a fresh directory, removed afterwards.
    static func withWriter(on dongle: FakeDongle, _ body: (Fixture) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ja11-writer-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(fileURL: directory.appendingPathComponent("user1-original.json"))
        let device = try await ApplyTests.makeDevice(on: dongle)
        try await body(Fixture(writer: JA11Writer(device: device, store: store), store: store, dongle: dongle))
    }

    static func thrown(_ work: () async throws -> Void) async -> (any Error)? {
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }

    /// The dongle's original USER1 contents as a curve.
    static let originalCurve = EQCurve(state: EQState(slotID: 3, preGain: 0.0, bands: FakeDongle.originalBands))!

    static func backup(activeSlot: UInt8 = JA11SlotID.user1, curve: EQCurve = originalCurve) -> DeviceBackup {
        DeviceBackup(savedAt: Date(timeIntervalSince1970: 1_791_000_000), activeSlot: activeSlot, curve: curve)
    }

    /// Notes, for every write frame the dongle receives, whether the backup file exists by then.
    static func recordBackupPresence(on dongle: FakeDongle, store: BackupStore) -> Recorder<Bool> {
        let presence = Recorder<Bool>()
        dongle.onWrite = { _ in presence.append(store.exists) }
        return presence
    }

    // MARK: - backup() (D-13)

    @Test func backupWithUser1ActiveSavesItsContentsAndSendsNoWriteFrame() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let outcome = try await fixture.writer.backup()

            guard case .created(let backup) = outcome else {
                Issue.record("expected .created, got \(outcome)")
                return
            }
            #expect(fixture.store.exists)
            #expect(backup.formatVersion == 1)
            #expect(backup.activeSlot == 3)
            #expect(backup.curve == Self.originalCurve)
            #expect(try fixture.store.load() == backup)
            #expect(dongle.writeFrames.isEmpty)
        }
    }

    @Test func backupFromAFactorySlotReadsUser1AndPutsTheSlotBack() async throws {
        let dongle = FakeDongle(slot: JA11SlotID.vocal)
        try await Self.withWriter(on: dongle) { fixture in
            let outcome = try await fixture.writer.backup()

            #expect(dongle.writeFrames == [ApplyTests.selectFrame(3), ApplyTests.selectFrame(0)])
            #expect(outcome.backup.activeSlot == 0)
            // USER1's contents, not Vocal's.
            #expect(outcome.backup.curve == Self.originalCurve)
            #expect(outcome.backup.curve.bands[2].frequency == 704)
            #expect(dongle.state.slotID == JA11SlotID.vocal)
            #expect(try fixture.store.load() == outcome.backup)
        }
    }

    @Test func backupWithAFileAlreadyThereKeepsItAndSendsNothingAtAll() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let earlier = Self.backup(activeSlot: 1, curve: ApplyTests.testCurve)
            #expect(try fixture.store.saveIfAbsent(earlier))
            let bytes = try Data(contentsOf: fixture.store.fileURL)

            let outcome = try await fixture.writer.backup()

            #expect(outcome == .kept(earlier))
            #expect(dongle.transport.sent.isEmpty)
            #expect(try Data(contentsOf: fixture.store.fileURL) == bytes)
        }
    }

    @Test(arguments: [true, false])
    func backupOfAStateThatCannotBeWrittenBackThrowsAndCreatesNoFile(fourFilters: Bool) async throws {
        let dongle = fourFilters ? FakeDongle(filterCount: 4) : FakeDongle(typeOverride: (index: 2, typeID: 7))
        try await Self.withWriter(on: dongle) { fixture in
            let error = await Self.thrown { _ = try await fixture.writer.backup() }

            guard case JA11Error.unexpectedReply = try #require(error) else {
                Issue.record("expected unexpectedReply, got \(String(describing: error))")
                return
            }
            #expect(!fixture.store.exists)
            #expect(dongle.writeFrames.isEmpty)

            // And without a backup, an apply writes nothing either.
            let applyError = await Self.thrown { _ = try await fixture.writer.apply(ApplyTests.testCurve) }
            #expect(applyError != nil)
            #expect(dongle.writeFrames.isEmpty)
        }
    }

    // MARK: - Backup before every write (D-13, T-02-06)

    @Test func applyWithoutAFileHasTheBackupOnDiskBeforeTheFirstWriteFrame() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let presence = Self.recordBackupPresence(on: dongle, store: fixture.store)

            let report = try await fixture.writer.apply(ApplyTests.testCurve)

            #expect(report.isConfirmed)
            #expect(presence.values.count == 9)
            #expect(presence.values.allSatisfy { $0 })
            #expect(try fixture.store.load().curve == Self.originalCurve)
            #expect(dongle.writeFrames == ApplyTests.pinnedFrames)
        }
    }

    @Test func applyWithAFileAlreadyThereLeavesItsBytesUnchanged() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            #expect(try fixture.store.saveIfAbsent(Self.backup(activeSlot: 2, curve: ApplyTests.testCurve)))
            let bytes = try Data(contentsOf: fixture.store.fileURL)

            let first = try await fixture.writer.apply(ApplyTests.testCurve)
            let second = try await fixture.writer.apply(ApplyTests.testCurve)

            #expect(first.isConfirmed)
            #expect(second.isConfirmed)
            #expect(try Data(contentsOf: fixture.store.fileURL) == bytes)
        }
    }

    @Test func anUnreadableBackupStopsEveryWriteAndIsLeftUntouched() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            try BackupStoreTests.write("not json", to: fixture.store)
            let writer = fixture.writer

            let errors = [
                await Self.thrown { _ = try await writer.apply(ApplyTests.testCurve) },
                await Self.thrown { _ = try await writer.applyTestCurve() },
                await Self.thrown { _ = try await writer.selectSlot(.vocal) },
                await Self.thrown { _ = try await writer.restore() },
                await Self.thrown { _ = try await writer.backup() },
            ]

            #expect(errors.count == 5)
            #expect(errors.allSatisfy { BackupStoreTests.isUnreadable($0 as? BackupError) })
            #expect(dongle.transport.sent.isEmpty)
            #expect(try Data(contentsOf: fixture.store.fileURL) == Data("not json".utf8))
        }
    }

    // MARK: - restore() (D-14)

    @Test func restoreWithoutAFileThrowsMissingAndSendsNothing() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let error = await Self.thrown { _ = try await fixture.writer.restore() }

            #expect(BackupStoreTests.isMissing(error as? BackupError))
            #expect(dongle.transport.sent.isEmpty)
            #expect(!fixture.store.exists)
        }
    }

    @Test func restoreAfterTheTestCurvePutsTheOriginalUser1Back() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let original = dongle.user1
            #expect(try await fixture.writer.applyTestCurve().isConfirmed)
            #expect(dongle.user1 != original)
            let bytes = try Data(contentsOf: fixture.store.fileURL)

            let report = try await fixture.writer.restore()

            #expect(report.isConfirmed)
            #expect(report.apply.isConfirmed)
            #expect(report.expectedSlotID == 3)
            #expect(report.finalSlotID == 3)
            #expect(dongle.user1 == original)
            #expect(try Data(contentsOf: fixture.store.fileURL) == bytes)
        }
    }

    @Test func restoreReselectsTheSlotThatWasActiveAtBackupTime() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            #expect(try fixture.store.saveIfAbsent(Self.backup(activeSlot: JA11SlotID.vocal)))

            let report = try await fixture.writer.restore()

            #expect(report.isConfirmed)
            #expect(report.expectedSlotID == 0)
            #expect(report.finalSlotID == 0)
            #expect(dongle.writeFrames.last == ApplyTests.selectFrame(0))
            #expect(dongle.writeFrames.count == 10)
            #expect(dongle.state.slotID == JA11SlotID.vocal)
            #expect(dongle.user1.bands == FakeDongle.originalBands)
        }
    }

    @Test func restoreFromAFactorySlotSelectsUser1AndConfirmsItBeforeAnyValue() async throws {
        let dongle = FakeDongle(slot: JA11SlotID.vocal)
        try await Self.withWriter(on: dongle) { fixture in
            #expect(try fixture.store.saveIfAbsent(Self.backup()))

            let report = try await fixture.writer.restore()

            #expect(report.isConfirmed)
            #expect(report.finalSlotID == 3)
            let sent = dongle.transport.sent
            #expect(dongle.writeFrames.first == ApplyTests.selectFrame(3))
            let select = try #require(sent.firstIndex(of: ApplyTests.selectFrame(3)))
            let preGain = try #require(sent.firstIndex { ApplyTests.isWriteFrame($0) && $0[4] == 0x17 })
            #expect(Array(sent[(select + 1)..<preGain]) == [FiioFrame.getRequest(.presetSlot)])
        }
    }

    @Test func restoreOnADongleThatDoesNotSwitchToUser1WritesNoValue() async throws {
        let dongle = FakeDongle(slot: JA11SlotID.vocal, ignoresSelect: true)
        try await Self.withWriter(on: dongle) { fixture in
            let written = try fixture.store.saveIfAbsent(Self.backup())
            #expect(written)

            let error = await Self.thrown { _ = try await fixture.writer.restore() }

            #expect(ApplyTests.isWriteInterrupted(error as? JA11Error))
            #expect(ApplyTests.noValueOrSave(in: dongle.transport.sent))
            #expect(dongle.writeFrames == [ApplyTests.selectFrame(3)])
        }
    }

    @Test func aRestoreThatIsNotConfirmedDoesNotSelectTheOriginalSlot() async throws {
        let dongle = FakeDongle(ignoresFilters: true)
        try await Self.withWriter(on: dongle) { fixture in
            #expect(try fixture.store.saveIfAbsent(Self.backup(activeSlot: JA11SlotID.vocal, curve: ApplyTests.testCurve)))

            let report = try await fixture.writer.restore()

            #expect(!report.isConfirmed)
            #expect(!report.apply.isConfirmed)
            #expect(report.expectedSlotID == 0)
            #expect(report.finalSlotID == 3)
            #expect(!dongle.writeFrames.contains(ApplyTests.selectFrame(0)))
            #expect(dongle.writeFrames.count == 9)
        }
    }

    // MARK: - The test curve (D-16)

    @Test func applyTestCurveSendsTheNinePinnedFramesAndIsConfirmed() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let report = try await fixture.writer.applyTestCurve()

            #expect(report.isConfirmed)
            #expect(dongle.writeFrames == ApplyTests.pinnedFrames)
            #expect(try fixture.store.load().curve == Self.originalCurve)
        }
    }

    @Test func theTestCurveKeepsTypeFrequencyAndQOfBandsTwoToFourAtZeroGain() {
        let original = EQCurve(
            preGain: 3.0,
            bands: [
                EQBand(type: .peak, frequency: 40, gain: 1.0, q: 2.0),
                EQBand(type: .peak, frequency: 50, gain: 2.0, q: 3.0),
                EQBand(type: .lowShelf, frequency: 250, gain: 4.5, q: 0.55),
                EQBand(type: .peak, frequency: 3100, gain: -7.0, q: 4.25, enabled: false),
                EQBand(type: .highShelf, frequency: 9000, gain: 12.0, q: 0.9),
            ]
        )

        let curve = EQCurve.testCurve(basedOn: original)

        #expect(curve.preGain == -6.0)
        #expect(curve.bands == [
            EQBand(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.70),
            EQBand(type: .peak, frequency: 1000, gain: -3.0, q: 1.00),
            EQBand(type: .lowShelf, frequency: 250, gain: 0.0, q: 0.55),
            EQBand(type: .peak, frequency: 3100, gain: 0.0, q: 4.25),
            EQBand(type: .highShelf, frequency: 9000, gain: 0.0, q: 0.9),
        ])
        #expect(EQCurve.testCurve(basedOn: Self.originalCurve) == ApplyTests.testCurve)

        // A short original is padded first, so bands 2 to 4 always exist.
        let short = EQCurve.testCurve(basedOn: EQCurve(preGain: 0.0, bands: []))
        #expect(short.bands.count == 5)
        #expect(short.bands[4] == EQBand(type: .peak, frequency: 1000, gain: 0.0, q: 1.0))
    }

    // MARK: - selectSlot (D-12, D-13)

    @Test func selectSlotTakesTheBackupFirstAndReportsTheSlotReadBack() async throws {
        let dongle = FakeDongle()
        try await Self.withWriter(on: dongle) { fixture in
            let presence = Self.recordBackupPresence(on: dongle, store: fixture.store)

            let report = try await fixture.writer.selectSlot(.vocal)

            #expect(report.requested == .vocal)
            #expect(report.readSlotID == 0)
            #expect(report.isConfirmed)
            #expect(presence.values == [true])
            #expect(dongle.writeFrames == [ApplyTests.selectFrame(0)])
            #expect(try fixture.store.load().activeSlot == 3)
        }
    }

    @Test func selectSlotOnADongleThatIgnoresTheSelectFrameIsNotConfirmed() async throws {
        let dongle = FakeDongle(ignoresSelect: true)
        try await Self.withWriter(on: dongle) { fixture in
            let report = try await fixture.writer.selectSlot(.vocal)

            #expect(report.requested == .vocal)
            #expect(report.readSlotID == 3)
            #expect(!report.isConfirmed)
        }
    }
}
