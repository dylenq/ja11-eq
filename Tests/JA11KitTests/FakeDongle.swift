import Foundation
@testable import JA11Kit

/// A JA11 that exists only in memory. It owns a `FakeTransport` and plays the dongle's part through
/// that transport's responder: a write frame changes its working state, a read request is answered
/// from it. It never calls IOKit, so nothing here can reach a real dongle.
///
/// Each preset slot has its own saved contents. Selecting a slot loads that slot's contents into
/// the working state; value frames change the working state; a save stores it in the named slot.
final class FakeDongle: @unchecked Sendable {
    /// What the real dongle held in USER1 when Phase 1 read it: every gain 0.0 dB.
    static let originalBands: [Band] = [
        Band(index: 0, typeID: 1, frequency: 59, gain: 0.0, q: 0.70),
        Band(index: 1, typeID: 0, frequency: 181, gain: 0.0, q: 0.62),
        Band(index: 2, typeID: 0, frequency: 704, gain: 0.0, q: 1.20),
        Band(index: 3, typeID: 0, frequency: 7171, gain: 0.0, q: 1.50),
        Band(index: 4, typeID: 2, frequency: 3973, gain: 0.0, q: 0.40),
    ]

    /// Made-up contents for the factory slots, different from USER1's, so a read in a factory slot
    /// cannot pass for a read of USER1.
    static let factoryBands: [Band] = [
        Band(index: 0, typeID: 1, frequency: 80, gain: -2.0, q: 0.70),
        Band(index: 1, typeID: 0, frequency: 300, gain: -1.5, q: 1.00),
        Band(index: 2, typeID: 0, frequency: 2500, gain: 3.0, q: 1.40),
        Band(index: 3, typeID: 0, frequency: 5000, gain: 2.0, q: 2.00),
        Band(index: 4, typeID: 2, frequency: 10000, gain: 1.0, q: 0.70),
    ]

    /// What one slot holds.
    struct Contents {
        var preGainTenths = 0
        var filterCount = 5
        var bands: [Band]
    }

    /// What the dongle does once it has received a save frame.
    enum AfterSave: Sendable {
        /// Stays connected and answers.
        case stays
        /// Drops off USB at once and comes back after the given time.
        case dropsAndReturns(after: Duration)
        /// Drops off USB at once and does not come back.
        case dropsForGood
        /// Stays connected but answers no read request any more.
        case silent
        /// Reports this slot from then on, whatever is selected.
        case reportsSlot(UInt8)
    }

    let transport = FakeTransport()

    private let lock = NSLock()
    private var slot: UInt8
    private var working: Contents
    private var saved: [UInt8: Contents]
    private let ignoresWrites: Bool
    private let ignoresSelect: Bool
    private let ignoresFilters: Bool
    private let gainError: (index: Int, tenths: Int)?
    private let afterSave: AfterSave
    private var away = false
    private var silent = false
    private var slotStuck = false
    private var writeObserver: (@Sendable ([UInt8]) -> Void)?

    /// - Parameters:
    ///   - slot: the preset slot that is active at the start.
    ///   - ignoresWrites: every write frame is dropped, as if the device did not understand it.
    ///   - ignoresSelect: only preset-switch frames are dropped.
    ///   - ignoresFilters: only filter frames are dropped.
    ///   - gainError: the filter at `index` is stored with its gain off by `tenths` of a dB.
    ///   - afterSave: what happens once a save frame has arrived.
    ///   - filterCount: the filter count USER1 reports at the start.
    ///   - typeOverride: USER1's filter at `index` starts with this type number.
    init(
        slot: UInt8 = JA11SlotID.user1,
        ignoresWrites: Bool = false,
        ignoresSelect: Bool = false,
        ignoresFilters: Bool = false,
        gainError: (index: Int, tenths: Int)? = nil,
        afterSave: AfterSave = .stays,
        filterCount: Int = 5,
        typeOverride: (index: Int, typeID: UInt8)? = nil
    ) {
        var user1 = Contents(filterCount: filterCount, bands: FakeDongle.originalBands)
        if let typeOverride {
            user1.bands[typeOverride.index].typeID = typeOverride.typeID
        }
        var saved: [UInt8: Contents] = [:]
        for factory in [JA11SlotID.vocal, JA11SlotID.classic, JA11SlotID.bass, JA11SlotID.off] {
            saved[factory] = Contents(preGainTenths: -20, bands: FakeDongle.factoryBands)
        }
        saved[JA11SlotID.user1] = user1

        self.slot = slot
        self.saved = saved
        self.working = saved[slot] ?? user1
        self.ignoresWrites = ignoresWrites
        self.ignoresSelect = ignoresSelect
        self.ignoresFilters = ignoresFilters
        self.gainError = gainError
        self.afterSave = afterSave
        transport.responder = { [unowned self] payload in self.respond(to: payload) }
    }

    /// The working state as a full read would report it.
    var state: EQState {
        lock.withLock { Self.state(slot: slot, working) }
    }

    /// What USER1 holds, as a read with USER1 active would report it.
    var user1: EQState {
        lock.withLock { Self.state(slot: JA11SlotID.user1, saved[JA11SlotID.user1]!) }
    }

    /// Called for every write frame, before the frame takes effect.
    var onWrite: (@Sendable ([UInt8]) -> Void)? {
        get { lock.withLock { writeObserver } }
        set { lock.withLock { writeObserver = newValue } }
    }

    /// The write frames handed to the transport so far: the payloads that start with the write header.
    var writeFrames: [[UInt8]] {
        transport.sent.filter { $0.starts(with: [0xAA, 0x0A]) }
    }

    private static func state(slot: UInt8, _ contents: Contents) -> EQState {
        EQState(
            slotID: slot,
            preGain: Double(contents.preGainTenths) / 10,
            bands: Array(contents.bands.prefix(contents.filterCount))
        )
    }

    private func respond(to payload: [UInt8]) -> [[UInt8]] {
        let isWrite = payload.starts(with: [0xAA, 0x0A])
        if isWrite { onWrite?(payload) }

        return lock.withLock {
            guard !away else { return [] }
            guard payload.count == JA11.payloadLength, payload[2] == 0x00, payload[3] == 0x00 else { return [] }
            if isWrite {
                store(payload)
                return []
            }
            if payload.starts(with: [0xBB, 0x0B]), !silent {
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
            guard !ignoresSelect, !slotStuck else { return }
            slot = frame[6]
            if let contents = saved[slot] { working = contents }
        case (0x17, 2):
            working.preGainTenths = FiioFrame.int16BE(frame[6], frame[7])
        case (0x18, 1):
            working.filterCount = Int(frame[6])
        case (0x15, 8):
            let index = Int(frame[6])
            guard !ignoresFilters, working.bands.indices.contains(index) else { return }
            var tenths = FiioFrame.int16BE(frame[7], frame[8])
            if let gainError, gainError.index == index { tenths += gainError.tenths }
            working.bands[index] = Band(
                index: index,
                typeID: frame[13],
                frequency: FiioFrame.uint16BE(frame[9], frame[10]),
                gain: Double(tenths) / 10,
                q: Double(FiioFrame.uint16BE(frame[11], frame[12])) / 100
            )
        case (0x19, 1):
            saved[frame[6]] = working
            afterSaveBehaviour()
        default:
            return
        }
    }

    private func afterSaveBehaviour() {
        switch afterSave {
        case .stays:
            break
        case .dropsAndReturns(let delay):
            away = true
            transport.emit(.disconnected)
            Task {
                try? await Task.sleep(for: delay)
                self.comeBack()
            }
        case .dropsForGood:
            away = true
            transport.emit(.disconnected)
        case .silent:
            silent = true
        case .reportsSlot(let other):
            slot = other
            slotStuck = true
        }
    }

    /// Back on USB, with the active slot's saved contents as the working state.
    private func comeBack() {
        lock.withLock {
            away = false
            if let contents = saved[slot] { working = contents }
        }
        transport.emit(.connected)
    }

    /// The reply frame for a read request, or nil for one this dongle does not understand.
    private func reply(to request: [UInt8]) -> [UInt8]? {
        let data: [UInt8]
        switch (request[4], request[5]) {
        case (0x16, 0):
            data = [slot]
        case (0x18, 0):
            data = [UInt8(working.filterCount)]
        case (0x17, 0):
            data = Self.bigEndian(working.preGainTenths)
        case (0x15, 1):
            let index = Int(request[6])
            guard working.bands.indices.contains(index) else { return nil }
            let band = working.bands[index]
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
