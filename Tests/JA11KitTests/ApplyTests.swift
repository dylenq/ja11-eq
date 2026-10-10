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
    static func makeDevice(on dongle: FakeDongle) async throws -> JA11Device {
        let device = JA11Device(
            transport: dongle.transport,
            replyTimeout: .milliseconds(100),
            discoveryTimeout: .milliseconds(100),
            framePause: .milliseconds(1),
            saveSettle: .milliseconds(1),
            reconnectTimeout: .milliseconds(500)
        )
        await device.start()
        dongle.transport.emit(.connected)
        try await device.waitForConnection()
        return device
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
        #expect(dongle.state.bands == FakeDongle.originalBands)
    }
}
