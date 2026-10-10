import Foundation
@testable import JA11Kit

/// A JA11 that exists only in memory. It owns a `FakeTransport` and plays the dongle's part through
/// that transport's responder: a write frame changes its working state, a read request is answered
/// from it. It never calls IOKit, so nothing here can reach a real dongle.
final class FakeDongle: @unchecked Sendable {
    /// What the real dongle held when Phase 1 read it: every gain 0.0 dB.
    static let originalBands: [Band] = [
        Band(index: 0, typeID: 1, frequency: 59, gain: 0.0, q: 0.70),
        Band(index: 1, typeID: 0, frequency: 181, gain: 0.0, q: 0.62),
        Band(index: 2, typeID: 0, frequency: 704, gain: 0.0, q: 1.20),
        Band(index: 3, typeID: 0, frequency: 7171, gain: 0.0, q: 1.50),
        Band(index: 4, typeID: 2, frequency: 3973, gain: 0.0, q: 0.40),
    ]

    let transport = FakeTransport()

    private let lock = NSLock()
    private var slot: UInt8
    private var preGainTenths = 0
    private var filterCount = 5
    private var bands = FakeDongle.originalBands
    private let ignoresWrites: Bool
    private let ignoresSelect: Bool

    /// - Parameters:
    ///   - slot: the preset slot that is active at the start.
    ///   - ignoresWrites: every write frame is dropped, as if the device did not understand it.
    ///   - ignoresSelect: only preset-switch frames are dropped.
    init(slot: UInt8 = JA11SlotID.user1, ignoresWrites: Bool = false, ignoresSelect: Bool = false) {
        self.slot = slot
        self.ignoresWrites = ignoresWrites
        self.ignoresSelect = ignoresSelect
        transport.responder = { [unowned self] payload in self.respond(to: payload) }
    }

    /// The working state as a full read would report it.
    var state: EQState {
        lock.withLock {
            EQState(slotID: slot, preGain: Double(preGainTenths) / 10, bands: Array(bands.prefix(filterCount)))
        }
    }

    /// The write frames received so far: the payloads that start with the write header.
    var writeFrames: [[UInt8]] {
        transport.sent.filter { $0.starts(with: [0xAA, 0x0A]) }
    }

    private func respond(to payload: [UInt8]) -> [[UInt8]] {
        lock.withLock {
            guard payload.count == JA11.payloadLength, payload[2] == 0x00, payload[3] == 0x00 else { return [] }
            if payload.starts(with: [0xAA, 0x0A]) {
                store(payload)
                return []
            }
            if payload.starts(with: [0xBB, 0x0B]) {
                return reply(to: payload).map { [Self.report($0)] } ?? []
            }
            return []
        }
    }

    /// Takes the values of a write frame into the working state.
    private func store(_ frame: [UInt8]) {
        guard !ignoresWrites else { return }
        switch (frame[4], frame[5]) {
        case (0x16, 1):
            if !ignoresSelect { slot = frame[6] }
        case (0x17, 2):
            preGainTenths = FiioFrame.int16BE(frame[6], frame[7])
        case (0x18, 1):
            filterCount = Int(frame[6])
        case (0x15, 8):
            let index = Int(frame[6])
            guard bands.indices.contains(index) else { return }
            bands[index] = Band(
                index: index,
                typeID: frame[13],
                frequency: FiioFrame.uint16BE(frame[9], frame[10]),
                gain: Double(FiioFrame.int16BE(frame[7], frame[8])) / 10,
                q: Double(FiioFrame.uint16BE(frame[11], frame[12])) / 100
            )
        default:
            return      // the save changes nothing a read would show
        }
    }

    /// The reply frame for a read request, or nil for one this dongle does not understand.
    private func reply(to request: [UInt8]) -> [UInt8]? {
        let data: [UInt8]
        switch (request[4], request[5]) {
        case (0x16, 0):
            data = [slot]
        case (0x18, 0):
            data = [UInt8(filterCount)]
        case (0x17, 0):
            data = Self.bigEndian(preGainTenths)
        case (0x15, 1):
            let index = Int(request[6])
            guard bands.indices.contains(index) else { return nil }
            let band = bands[index]
            data = [UInt8(index)]
                + Self.bigEndian(Int((band.gain * 10).rounded()))
                + Self.bigEndian(band.frequency)
                + Self.bigEndian(Int((band.q * 100).rounded()))
                + [band.typeID]
        default:
            return nil
        }
        return [0xBB, 0x0B, 0x00, 0x00, request[4], UInt8(data.count)] + data + [0x00, 0xEE]
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        let bits = UInt16(truncatingIfNeeded: value)
        return [UInt8(bits >> 8), UInt8(bits & 0xFF)]
    }

    /// A reply as the real device delivers it: 21 bytes, the report-ID byte first.
    private static func report(_ frame: [UInt8]) -> [UInt8] {
        [JA11.reportID] + frame + [UInt8](repeating: 0x00, count: JA11.payloadLength - frame.count)
    }
}
