/// The two forms in which a read request may be handed to the JA11.
public enum FrameForm: String, Sendable, CaseIterable {
    /// Zero-padded to the full 20-byte report: the primary form.
    case padded
    /// The bare 8- or 9-byte frame: the fallback when the padded form goes unanswered.
    case unpadded
}

/// A reply located inside an input report.
public struct FiioReplyFrame: Sendable, Equatable {
    /// Where the reply header was found in the report: 0, or 1 when macOS delivered a leading report-ID byte.
    public let headerOffset: Int
    /// The command this reply answers (frame byte 4).
    public let command: UInt8
    /// The frame, from its header to the end of the report.
    public let bytes: [UInt8]

    /// The active preset slot, when this is a reply to the preset-slot request.
    public func slotID() -> UInt8? {
        guard command == JA11Command.presetSlot.rawValue else { return nil }
        return byte(at: 6)
    }

    /// The number of filters in use, when this is a reply to the filter-count request.
    public func filterCount() -> Int? {
        guard command == JA11Command.filterCount.rawValue, let count = byte(at: 6) else { return nil }
        return Int(count)
    }

    /// The pre-gain in dB, when this is a reply to the pre-gain request.
    ///
    /// Frame bytes 6 and 7 hold dB × 10 as a signed big-endian number.
    public func preGain() -> Double? {
        guard command == JA11Command.preGain.rawValue, bytes.count >= 8 else { return nil }
        return Double(FiioFrame.int16BE(bytes[6], bytes[7])) / 10
    }

    /// The filter this reply describes, when this is a reply to a filter request.
    ///
    /// Frame byte 6 is the index, 7–8 the gain (dB × 10, signed), 9–10 the frequency in Hz,
    /// 11–12 Q × 100 and 13 the type. Every value is passed on as received: a Q of 0 stays 0 and
    /// an unknown type number stays that number.
    public func band() -> Band? {
        guard command == JA11Command.filter.rawValue, bytes.count >= 14 else { return nil }
        return Band(
            index: Int(bytes[6]),
            typeID: bytes[13],
            frequency: FiioFrame.uint16BE(bytes[9], bytes[10]),
            gain: Double(FiioFrame.int16BE(bytes[7], bytes[8])) / 10,
            q: Double(FiioFrame.uint16BE(bytes[11], bytes[12])) / 100
        )
    }

    /// One frame byte, or nil when the frame is too short to hold it.
    private func byte(at index: Int) -> UInt8? {
        bytes.indices.contains(index) ? bytes[index] : nil
    }
}

/// Builds requests for the JA11, locates replies in its input reports, and decides which frames
/// may be sent at all.
///
/// Read (GET) requests exist for the four read commands. Write (SET) frames exist for the five
/// commands of `JA11WriteCommand` and nothing else: each has its own builder, every builder clamps
/// its values to the device limits, and the only save builder is for USER1. `isPermittedFrame` is
/// the allow-list the transport applies before anything reaches the device.
public enum FiioFrame {
    /// First two bytes of every read request and of every reply.
    static let header: [UInt8] = [0xBB, 0x0B]
    /// First two bytes of every write frame.
    static let setHeader: [UInt8] = [0xAA, 0x0A]
    /// Last two bytes of a request, after its data.
    static let terminator: [UInt8] = [0x00, 0xEE]
    /// A reply needs its header, two reserved bytes, command, length and at least one data byte.
    static let minimumReplyLength = 7

    /// The read request for `command`, in the given form.
    ///
    /// `.unpadded` gives the bare frame, 8 bytes plus the data; `.padded` adds zero bytes up to the
    /// 20-byte report length.
    public static func getRequest(_ command: JA11Command, data: [UInt8] = [], form: FrameForm = .padded) -> [UInt8] {
        var frame = header + [0x00, 0x00, command.rawValue, UInt8(clamping: data.count)] + data + terminator
        if form == .padded, frame.count < JA11.payloadLength {
            frame += [UInt8](repeating: 0x00, count: JA11.payloadLength - frame.count)
        }
        return frame
    }

    /// Number of data bytes the read request for `command` carries: the filter index, or nothing.
    static func requestDataLength(for command: JA11Command) -> Int {
        command == .filter ? 1 : 0
    }

    /// True only for a payload that is, byte for byte, one of the four read requests in one of the
    /// two permitted forms. Together with `isSetRequest` it makes up the transport's gate.
    public static func isGetRequest(_ payload: [UInt8]) -> Bool {
        guard payload.count >= 8, payload.count <= JA11.payloadLength else { return false }
        guard Array(payload[0..<2]) == header, payload[2] == 0x00, payload[3] == 0x00 else { return false }
        guard let command = JA11Command(rawValue: payload[4]) else { return false }

        let dataLength = Int(payload[5])
        guard dataLength == requestDataLength(for: command) else { return false }

        let frameLength = 6 + dataLength + terminator.count
        guard payload.count >= frameLength else { return false }
        guard Array(payload[(frameLength - terminator.count)..<frameLength]) == terminator else { return false }

        if payload.count == frameLength { return true }                    // unpadded
        guard payload.count == JA11.payloadLength else { return false }    // padded: exactly one full report
        return payload[frameLength...].allSatisfy { $0 == 0x00 }
    }

    // MARK: - Write frames

    /// The write frame for `command` with `data`: always the zero-padded 20-byte form.
    private static func setFrame(_ command: JA11WriteCommand, data: [UInt8]) -> [UInt8] {
        precondition(data.count == command.dataLength, "write frame data must be \(command.dataLength) bytes")
        let frame = setHeader + [0x00, 0x00, command.rawValue, UInt8(command.dataLength)] + data + terminator
        return frame + [UInt8](repeating: 0x00, count: JA11.payloadLength - frame.count)
    }

    /// A number as two bytes, high byte first; a negative one in two's complement.
    private static func bigEndian16(_ value: Int) -> [UInt8] {
        let bits = UInt16(truncatingIfNeeded: value)
        return [UInt8(bits >> 8), UInt8(bits & 0xFF)]
    }

    /// Sets the pre-gain, clamped to the device limit.
    static func setPreGain(_ dB: Double) -> [UInt8] {
        setFrame(.preGain, data: bigEndian16(JA11Limits.preGainTenths(dB)))
    }

    /// Sets the number of filters in use, clamped to 0...5.
    static func setFilterCount(_ count: Int) -> [UInt8] {
        setFrame(.filterCount, data: [UInt8(min(max(count, 0), JA11Limits.maxBands))])
    }

    /// Sets one filter: index, gain, frequency, Q and type, each value clamped to the device limit.
    ///
    /// The index has to be one of the device's filter positions and the type one of its three
    /// shapes; anything else is a programming error, and no frame is built.
    static func setFilter(_ band: Band) -> [UInt8] {
        precondition(
            (0..<JA11Limits.maxBands).contains(band.index),
            "filter index \(band.index) is outside 0..<\(JA11Limits.maxBands)"
        )
        precondition(band.typeID <= maxFilterTypeID, "filter type \(band.typeID) is not one the JA11 offers")
        let data = [UInt8(band.index)]
            + bigEndian16(JA11Limits.gainTenths(band.gain))
            + bigEndian16(JA11Limits.hertz(Double(band.frequency)))
            + bigEndian16(JA11Limits.qHundredths(band.q))
            + [band.typeID]
        return setFrame(.filter, data: data)
    }

    /// Makes `slot` the active preset.
    static func selectSlot(_ slot: PresetSlot) -> [UInt8] {
        setFrame(.presetSlot, data: [slot.rawValue])
    }

    /// Saves the working values to USER1. There is no builder that saves to any other slot.
    static func saveToUser1() -> [UInt8] {
        setFrame(.save, data: [JA11SlotID.user1])
    }

    /// Highest filter type number the JA11 offers (high shelf).
    private static let maxFilterTypeID: UInt8 = 2

    /// True only for a write frame this library may send: exactly 20 bytes, the write header, one
    /// of the five write commands with exactly its data length, a zero byte and the end byte
    /// straight after the data, zero bytes from there on, and data within the device limits.
    ///
    /// Per command: a save names slot 3 and no other; a preset switch names slot 0...4; a filter
    /// count is 0...5; a pre-gain is within -12...+12 dB; a filter has index 0...4, gain within
    /// -12...+12 dB, frequency 20...20000 Hz, Q 0.1...10 and type 0...2.
    public static func isSetRequest(_ payload: [UInt8]) -> Bool {
        guard payload.count == JA11.payloadLength else { return false }
        guard Array(payload[0..<2]) == setHeader, payload[2] == 0x00, payload[3] == 0x00 else { return false }
        guard let command = JA11WriteCommand(rawValue: payload[4]) else { return false }
        guard Int(payload[5]) == command.dataLength else { return false }

        let dataEnd = 6 + command.dataLength
        // The byte before the end byte is zero on every write frame; no other value is ever tried there.
        guard Array(payload[dataEnd..<(dataEnd + terminator.count)]) == terminator else { return false }
        guard payload[(dataEnd + terminator.count)...].allSatisfy({ $0 == 0x00 }) else { return false }

        let data = Array(payload[6..<dataEnd])
        let tenths = -120...120
        switch command {
        case .save:
            return data[0] == JA11SlotID.user1
        case .presetSlot:
            return PresetSlot(rawValue: data[0]) != nil
        case .filterCount:
            return Int(data[0]) <= JA11Limits.maxBands
        case .preGain:
            return tenths.contains(int16BE(data[0], data[1]))
        case .filter:
            return Int(data[0]) < JA11Limits.maxBands
                && tenths.contains(int16BE(data[1], data[2]))
                && JA11Limits.frequencyRange.contains(uint16BE(data[3], data[4]))
                && (10...1000).contains(uint16BE(data[5], data[6]))
                && data[7] <= maxFilterTypeID
        }
    }

    /// True for every frame the transport may send: a read request or a permitted write frame.
    public static func isPermittedFrame(_ payload: [UInt8]) -> Bool {
        isGetRequest(payload) || isSetRequest(payload)
    }

    // MARK: - Replies

    /// Locates a reply in an input report.
    ///
    /// macOS may deliver the report with or without a leading report-ID byte, so the header is
    /// looked for at offset 0 and then at offset 1, and nowhere else.
    public static func replyFrame(from report: [UInt8]) -> FiioReplyFrame? {
        for offset in 0...1 {
            guard report.count >= offset + header.count else { continue }
            guard Array(report[offset..<(offset + header.count)]) == header else { continue }
            let bytes = Array(report[offset...])
            guard bytes.count >= minimumReplyLength else { return nil }
            return FiioReplyFrame(headerOffset: offset, command: bytes[4], bytes: bytes)
        }
        return nil
    }

    /// Two bytes, high byte first, as a signed 16-bit number (two's complement).
    public static func int16BE(_ high: UInt8, _ low: UInt8) -> Int {
        Int(Int16(bitPattern: UInt16(high) << 8 | UInt16(low)))
    }

    /// Two bytes, high byte first, as an unsigned 16-bit number.
    public static func uint16BE(_ high: UInt8, _ low: UInt8) -> Int {
        Int(UInt16(high) << 8 | UInt16(low))
    }

    /// Bytes as two-digit lowercase hex separated by single spaces, e.g. `bb 0b 00`.
    public static func hex(_ bytes: [UInt8]) -> String {
        bytes
            .map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }
            .joined(separator: " ")
    }
}
