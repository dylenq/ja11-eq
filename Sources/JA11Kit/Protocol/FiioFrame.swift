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
        nil  // RED stub: replaced in the implementation commit
    }

    /// The pre-gain in dB, when this is a reply to the pre-gain request.
    public func preGain() -> Double? {
        nil  // RED stub: replaced in the implementation commit
    }

    /// The filter this reply describes, when this is a reply to a filter request.
    public func band() -> Band? {
        nil  // RED stub: replaced in the implementation commit
    }

    /// One frame byte, or nil when the frame is too short to hold it.
    private func byte(at index: Int) -> UInt8? {
        bytes.indices.contains(index) ? bytes[index] : nil
    }
}

/// Builds read requests for the JA11 and locates replies in its input reports.
///
/// This type builds read (GET) requests only. Nothing in it can encode a frame that changes the DAC.
public enum FiioFrame {
    /// First two bytes of every read request and of every reply.
    static let header: [UInt8] = [0xBB, 0x0B]
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
    /// two permitted forms. This is the gate the transport applies before anything reaches the device.
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
        0  // RED stub: replaced in the implementation commit
    }

    /// Two bytes, high byte first, as an unsigned 16-bit number.
    public static func uint16BE(_ high: UInt8, _ low: UInt8) -> Int {
        0  // RED stub: replaced in the implementation commit
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
