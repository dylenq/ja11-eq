import Foundation
import Testing
@testable import JA11Kit

/// The write path from end to end: curve, clamping, write frames, apply order and read-back, on a
/// `FakeDongle`. Nothing here creates an `HIDTransport`, so nothing can reach a real dongle.
@Suite struct ApplyTests {
    // MARK: - The curve and the frames it has to produce (CONTEXT D-01, D-16)

    /// Pre-gain -6.0; low shelf 100 Hz +6.0 Q 0.70; peak 1000 Hz -3.0 Q 1.00; three bands at 0.0 dB.
    static let testCurve = EQCurve(
        preGain: -6.0,
        bands: [
            EQBand(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.70),
            EQBand(type: .peak, frequency: 1000, gain: -3.0, q: 1.00),
            EQBand(type: .peak, frequency: 704, gain: 0.0, q: 1.20),
            EQBand(type: .peak, frequency: 7171, gain: 0.0, q: 1.50),
            EQBand(type: .highShelf, frequency: 3973, gain: 0.0, q: 0.40),
        ]
    )

    static let selectSlot3: [UInt8] = [0xAA, 0x0A, 0x00, 0x00, 0x16, 0x01, 0x03, 0x00, 0xEE]

    /// The nine write frames of an apply of `testCurve`, in the order they have to be sent.
    static let pinnedFrames: [[UInt8]] = [
        [0xAA, 0x0A, 0x00, 0x00, 0x17, 0x02, 0xFF, 0xC4, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x18, 0x01, 0x05, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x00, 0x00, 0x3C, 0x00, 0x64, 0x00, 0x46, 0x01, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x01, 0xFF, 0xE2, 0x03, 0xE8, 0x00, 0x64, 0x00, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x02, 0x00, 0x00, 0x02, 0xC0, 0x00, 0x78, 0x00, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x03, 0x00, 0x00, 0x1C, 0x03, 0x00, 0x96, 0x00, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x15, 0x08, 0x04, 0x00, 0x00, 0x0F, 0x85, 0x00, 0x28, 0x02, 0x00, 0xEE],
        [0xAA, 0x0A, 0x00, 0x00, 0x19, 0x01, 0x03, 0x00, 0xEE],
        selectSlot3,
    ].map(padded)

    /// A frame zero-padded to one full report.
    static func padded(_ frame: [UInt8]) -> [UInt8] {
        frame + [UInt8](repeating: 0x00, count: max(0, JA11.payloadLength - frame.count))
    }

    static func isWriteFrame(_ payload: [UInt8]) -> Bool {
        payload.starts(with: [0xAA, 0x0A])
    }

    /// A started, connected device on the dongle's transport, with pauses short enough for tests.
    static func makeDevice(
        on dongle: FakeDongle,
        framePause: Duration = .milliseconds(1),
        reconnectTimeout: Duration = .milliseconds(500),
        connected: Bool = true
    ) async throws -> JA11Device {
        let device = JA11Device(
            transport: dongle.transport,
            replyTimeout: .milliseconds(100),
            discoveryTimeout: .milliseconds(100),
            framePause: framePause,
            saveSettle: .milliseconds(1),
            reconnectTimeout: reconnectTimeout,
            readBackRetryWait: .milliseconds(20)
        )
        await device.start()
        if connected {
            dongle.transport.emit(.connected)
            try await device.waitForConnection()
        }
        return device
    }

    static let saveFrame = pinnedFrames[7]

    static func selectFrame(_ slot: UInt8) -> [UInt8] {
        padded([0xAA, 0x0A, 0x00, 0x00, 0x16, 0x01, slot, 0x00, 0xEE])
    }

    /// Write frames with the given command byte.
    static func frames(_ command: UInt8, in payloads: [[UInt8]]) -> [[UInt8]] {
        payloads.filter { isWriteFrame($0) && $0[4] == command }
    }

    /// True when none of the frames that carry a value or a save is among the payloads.
    static func noValueOrSave(in payloads: [[UInt8]]) -> Bool {
        payloads.filter(isWriteFrame).allSatisfy { $0[4] == 0x16 }
    }

    static func isWriteInterrupted(_ error: JA11Error?) -> Bool {
        if case .writeInterrupted = error { return true }
        return false
    }

    static func isNoReadBack(_ error: JA11Error?) -> Bool {
        if case .noReadBack = error { return true }
        return false
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    // MARK: - Apply (D-09, D-10)

    @Test func applyWithUser1ActiveSendsTheNinePinnedFramesAndIsConfirmedByReadBack() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle)

        let report = try await device.apply(Self.testCurve)

        #expect(report.isConfirmed)
        #expect(report.differences.isEmpty)
        #expect(report.readBack.slotID == 3)
        #expect(report.readBack == report.sent)
        #expect(report.linkEvents.isEmpty)

        let sent = dongle.transport.sent
        #expect(sent.first == FiioFrame.getRequest(.presetSlot))
        #expect(sent.allSatisfy(FiioFrame.isPermittedFrame))
        #expect(sent.allSatisfy { $0.count == 20 })

        // No select frame in front of the pre-gain frame: slot 3 was already active.
        #expect(sent.filter(Self.isWriteFrame) == Self.pinnedFrames)

        // After the ninth write frame, nothing but the read-back: slot, count, pre-gain, five filters.
        let lastWrite = try #require(sent.lastIndex(where: Self.isWriteFrame))
        let after = Array(sent[(lastWrite + 1)...])
        #expect(after.allSatisfy(FiioFrame.isGetRequest))
        #expect(after.map { $0[4] } == [0x16, 0x18, 0x17, 0x15, 0x15, 0x15, 0x15, 0x15])
        #expect(after.suffix(5).map { $0[6] } == [0, 1, 2, 3, 4])
    }

    @Test func aDongleThatIgnoresWritesIsReportedAsAMismatchNotAsConfirmed() async throws {
        let dongle = FakeDongle(ignoresWrites: true)
        let device = try await Self.makeDevice(on: dongle)

        let report = try await device.apply(Self.testCurve)

        #expect(!report.isConfirmed)
        #expect(report.differences.contains("pre-gain: sent -6.0 dB, read +0.0 dB"))
        #expect(report.differences.contains("filter 0 gain: sent +6.0 dB, read +0.0 dB"))
        #expect(report.differences.contains("filter 0 frequency: sent 100 Hz, read 59 Hz"))
        #expect(report.readBack == dongle.state)
    }

    @Test func applyFromAFactorySlotSelectsUser1AndConfirmsItBeforeAnyValueIsSent() async throws {
        let dongle = FakeDongle(slot: JA11SlotID.vocal)
        let device = try await Self.makeDevice(on: dongle)

        let report = try await device.apply(Self.testCurve)

        #expect(report.isConfirmed)
        #expect(report.readBack.slotID == 3)

        let sent = dongle.transport.sent
        #expect(sent.first == FiioFrame.getRequest(.presetSlot))
        #expect(sent.allSatisfy(FiioFrame.isPermittedFrame))
        #expect(sent.filter(Self.isWriteFrame) == [Self.padded(Self.selectSlot3)] + Self.pinnedFrames)

        // The switch is read back before the pre-gain frame goes out.
        let select = try #require(sent.firstIndex(of: Self.padded(Self.selectSlot3)))
        let preGain = try #require(sent.firstIndex(of: Self.pinnedFrames[0]))
        #expect(select < preGain)
        #expect(sent[(select + 1)..<preGain] == [FiioFrame.getRequest(.presetSlot)])
    }

    @Test func anUnconfirmedSwitchToUser1EndsTheApplyBeforeAnyValueOrSaveIsSent() async throws {
        let dongle = FakeDongle(slot: JA11SlotID.vocal, ignoresSelect: true)
        let device = try await Self.makeDevice(on: dongle)

        await #expect {
            _ = try await device.apply(Self.testCurve)
        } throws: { error in
            guard case JA11Error.writeInterrupted = error else { return false }
            return true
        }

        // Exactly one write frame: the select. No pre-gain, count, filter or save frame.
        #expect(dongle.writeFrames == [Self.padded(Self.selectSlot3)])
        #expect(dongle.state.slotID == JA11SlotID.vocal)
        #expect(dongle.state.bands == FakeDongle.factoryBands)
        #expect(dongle.user1.bands == FakeDongle.originalBands)
    }

    @Test func aDisconnectBetweenTheLeadingSelectAndItsReadBackEndsTheApplyWithoutAnyValue() async throws {
        let dongle = FakeDongle(slot: JA11SlotID.vocal)
        dongle.onWrite = { [transport = dongle.transport] frame in
            if frame[4] == 0x16 { transport.emit(.disconnected) }
        }
        let device = try await Self.makeDevice(on: dongle, framePause: .milliseconds(20))

        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }

        #expect(Self.isWriteInterrupted(error))
        // The leading select went out once and was not tried again.
        #expect(dongle.writeFrames == [Self.selectFrame(3)])
    }

    // MARK: - After the save (D-10, WRITE-07)

    @Test func applySurvivesADropOffUSBAfterTheSaveAndIsConfirmed() async throws {
        let dongle = FakeDongle(afterSave: .dropsAndReturns(after: .milliseconds(50)))
        let device = try await Self.makeDevice(on: dongle)

        let report = try await device.apply(Self.testCurve)

        #expect(report.isConfirmed)
        #expect(report.readBack == report.sent)
        #expect(report.linkEvents.map(\.kind) == [.disconnected, .connected])
        let times = report.linkEvents.map(\.secondsAfterSave)
        #expect(times.count == 2 && times[0] >= 0 && times[0] < times[1])

        // Nothing but the select frame is sent after the save, and no value or save twice.
        let writes = dongle.writeFrames
        #expect(Self.frames(0x19, in: writes) == [Self.saveFrame])
        #expect(Self.frames(0x17, in: writes).count == 1)
        #expect(Self.frames(0x18, in: writes).count == 1)
        #expect(Self.frames(0x15, in: writes).count == 5)
        let save = try #require(writes.firstIndex(of: Self.saveFrame))
        let afterSave = writes[(save + 1)...]
        #expect(!afterSave.isEmpty)
        #expect(afterSave.allSatisfy { $0 == Self.selectFrame(3) })
        #expect(Array(writes[..<save]) == Array(Self.pinnedFrames[..<7]))
    }

    @Test func aDongleThatNeverComesBackEndsTheApplyWithNoReadBackAfterTheTimeout() async throws {
        let dongle = FakeDongle(afterSave: .dropsForGood)
        let device = try await Self.makeDevice(on: dongle, reconnectTimeout: .milliseconds(300))

        let start = ContinuousClock.now
        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }
        let elapsed = Self.seconds(ContinuousClock.now - start)

        #expect(Self.isNoReadBack(error))
        #expect(elapsed >= 0.3)
        #expect(elapsed < 1.3)
        #expect(Self.frames(0x19, in: dongle.writeFrames).count == 1)
        #expect(Self.frames(0x15, in: dongle.writeFrames).count == 5)
    }

    @Test func aDongleThatStaysSilentAfterTheSaveEndsTheApplyWithNoReadBack() async throws {
        let dongle = FakeDongle(afterSave: .silent)
        let device = try await Self.makeDevice(on: dongle, reconnectTimeout: .milliseconds(300))

        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }

        #expect(Self.isNoReadBack(error))
        #expect(Self.frames(0x19, in: dongle.writeFrames).count == 1)
        #expect(Self.frames(0x17, in: dongle.writeFrames).count == 1)
    }

    @Test func applyIsConfirmedWhileAWatcherReadsTheDeviceAfterTheReconnect() async throws {
        let dongle = FakeDongle(afterSave: .dropsAndReturns(after: .milliseconds(50)))
        let device = try await Self.makeDevice(on: dongle)
        let log = JA11DeviceTests.collect(device)
        #expect(await JA11DeviceTests.waitUntil { log.values.count == 2 })

        let report = try await device.apply(Self.testCurve)

        #expect(report.isConfirmed)
        #expect(Self.frames(0x19, in: dongle.writeFrames).count == 1)
        #expect(await JA11DeviceTests.waitUntil { log.values.contains(.disconnected) })
        #expect(log.values.filter { $0 == .connected }.count == 2)
    }

    // MARK: - Mismatch (WRITE-02)

    @Test func aGainStoredOneTenthOffIsReportedAsExactlyOneDifference() async throws {
        let dongle = FakeDongle(gainError: (index: 1, tenths: 1))
        let device = try await Self.makeDevice(on: dongle)

        let report = try await device.apply(Self.testCurve)

        #expect(!report.isConfirmed)
        #expect(report.differences == ["filter 1 gain: sent -3.0 dB, read -2.9 dB"])
    }

    @Test func aDongleThatReportsAnotherSlotAfterTheSaveIsAMismatch() async throws {
        let dongle = FakeDongle(afterSave: .reportsSlot(JA11SlotID.vocal))
        let device = try await Self.makeDevice(on: dongle)

        let report = try await device.apply(Self.testCurve)

        #expect(!report.isConfirmed)
        #expect(report.differences.first?.hasPrefix("slot: sent 3 (USER1), read 0 (Vocal)") == true)
    }

    // MARK: - Order, count and pause (D-06, D-09)

    @Test func aCurveWithTwoBandsStillSendsCountFiveAndFiveFiltersInIndexOrder() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle)
        let curve = EQCurve(
            preGain: 0.0,
            bands: [
                EQBand(type: .peak, frequency: 500, gain: 2.0, q: 1.00),
                EQBand(type: .highShelf, frequency: 8000, gain: 5.0, q: 0.80, enabled: false),
            ]
        )

        let report = try await device.apply(curve)

        #expect(report.isConfirmed)
        let writes = dongle.writeFrames
        #expect(Self.frames(0x18, in: writes).map { $0[6] } == [5])
        let filters = Self.frames(0x15, in: writes)
        #expect(filters.map { $0[6] } == [0, 1, 2, 3, 4])
        // The disabled band: gain 00 00, frequency 8000 Hz, Q 0.80 and high shelf as given.
        #expect(Array(filters[1][6..<16]) == [0x01, 0x00, 0x00, 0x1F, 0x40, 0x00, 0x50, 0x02, 0x00, 0xEE])
    }

    @Test func framesAreSentWithThePauseBetweenThem() async throws {
        let dongle = FakeDongle()
        let times = Recorder<ContinuousClock.Instant>()
        dongle.onWrite = { _ in times.append(ContinuousClock.now) }
        let device = try await Self.makeDevice(on: dongle, framePause: .milliseconds(30))

        _ = try await device.apply(Self.testCurve)

        let stamps = times.values
        #expect(stamps.count == 9)
        // Eight pauses of 30 ms lie between the pre-gain frame and the final select frame.
        #expect(Self.seconds(stamps[8] - stamps[0]) >= 0.2)
    }

    // MARK: - Interrupted before the save (WRITE-07, T-02-07)

    @Test func aDisconnectAfterTheThirdFilterEndsTheApplyWithoutASave() async throws {
        let dongle = FakeDongle()
        let filters = Recorder<UInt8>()
        dongle.onWrite = { [transport = dongle.transport] frame in
            guard frame[4] == 0x15 else { return }
            filters.append(frame[6])
            if filters.values.count == 3 { transport.emit(.disconnected) }
        }
        let device = try await Self.makeDevice(on: dongle, framePause: .milliseconds(20))

        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }

        #expect(Self.isWriteInterrupted(error))
        #expect(Self.frames(0x19, in: dongle.transport.sent).isEmpty)
        let count = dongle.transport.sent.count
        try await Task.sleep(for: .milliseconds(80))
        #expect(dongle.transport.sent.count == count)
        #expect(dongle.user1.bands == FakeDongle.originalBands)
    }

    @Test func aReplugBetweenTwoFiltersEndsTheApplyWithoutASave() async throws {
        let dongle = FakeDongle()
        let filters = Recorder<UInt8>()
        dongle.onWrite = { [transport = dongle.transport] frame in
            guard frame[4] == 0x15 else { return }
            filters.append(frame[6])
            if filters.values.count == 2 {
                transport.emit(.disconnected)
                transport.emit(.connected)
            }
        }
        let device = try await Self.makeDevice(on: dongle, framePause: .milliseconds(20))

        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }

        #expect(Self.isWriteInterrupted(error))
        #expect(Self.frames(0x19, in: dongle.transport.sent).isEmpty)
        let count = dongle.transport.sent.count
        try await Task.sleep(for: .milliseconds(80))
        #expect(dongle.transport.sent.count == count)
    }

    @Test func aSendErrorOnTheFourthSendEndsTheApplyWithoutASave() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle)
        // Slot request, pre-gain and count go through; the first filter frame fails.
        dongle.transport.failSends(with: .sendFailed(code: -1), afterSuccessful: 3)

        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }

        #expect(Self.isWriteInterrupted(error))
        #expect(dongle.transport.sent.count == 4)
        #expect(Self.frames(0x19, in: dongle.transport.sent).isEmpty)
        #expect(Self.frames(0x15, in: dongle.transport.sent).count == 1)
    }

    @Test func applyWithoutAConnectionSendsNothing() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle, connected: false)

        let error = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }

        #expect(error == .notConnected)
        #expect(dongle.transport.sent.isEmpty)
    }

    // MARK: - One write operation at a time, and twice in a row (WRITE-07)

    @Test func aSecondWriteOperationDuringAnApplyIsRefusedAsBusyAndSendsNothing() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle, framePause: .milliseconds(20))

        let first = Task { try await device.apply(Self.testCurve) }
        #expect(await JA11DeviceTests.waitUntil { !dongle.writeFrames.isEmpty })

        let second = await JA11DeviceTests.failure { try await device.apply(Self.testCurve) }
        let select = await JA11DeviceTests.failure { try await device.selectSlot(.vocal) }
        #expect(second == .busy)
        #expect(select == .busy)

        let report = try await first.value
        #expect(report.isConfirmed)
        #expect(dongle.writeFrames == Self.pinnedFrames)

        // The flag is released: the next operation runs.
        #expect(try await device.selectSlot(.user1) == 3)
    }

    @Test func theSameCurveAppliedTwiceSendsTheSameNineFramesAndIsConfirmedBothTimes() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle)

        let first = try await device.apply(Self.testCurve)
        let second = try await device.apply(Self.testCurve)

        #expect(first.isConfirmed)
        #expect(second.isConfirmed)
        #expect(first == second)
        #expect(dongle.writeFrames == Self.pinnedFrames + Self.pinnedFrames)
    }

    // MARK: - Preset switching (D-12, WRITE-08)

    @Test(arguments: PresetSlot.allCases)
    func selectSlotSendsOneSelectFrameAndReturnsTheSlotReadBack(slot: PresetSlot) async throws {
        let start = slot == .user1 ? JA11SlotID.vocal : JA11SlotID.user1
        let dongle = FakeDongle(slot: start)
        let device = try await Self.makeDevice(on: dongle)

        let read = try await device.selectSlot(slot)

        #expect(read == slot.rawValue)
        #expect(dongle.writeFrames == [Self.selectFrame(slot.rawValue)])
        #expect(dongle.state.slotID == slot.rawValue)
        #expect(dongle.transport.sent.allSatisfy(FiioFrame.isPermittedFrame))
    }

    @Test func selectSlotOnADongleThatIgnoresWritesReturnsTheOldSlotAndDoesNotThrow() async throws {
        let dongle = FakeDongle(ignoresWrites: true)
        let device = try await Self.makeDevice(on: dongle)

        let read = try await device.selectSlot(.bass)

        #expect(read == JA11SlotID.user1)
        #expect(dongle.writeFrames == [Self.selectFrame(2)])
    }

    @Test func selectSlotWithoutAConnectionSendsNothing() async throws {
        let dongle = FakeDongle()
        let device = try await Self.makeDevice(on: dongle, connected: false)

        let error = await JA11DeviceTests.failure { try await device.selectSlot(.vocal) }

        #expect(error == .notConnected)
        #expect(dongle.transport.sent.isEmpty)
    }
}
