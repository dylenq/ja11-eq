/// USB identity of the FiiO JadeAudio JA11 and the HID report that carries its EQ commands.
public enum JA11 {
    /// USB vendor ID (FiiO).
    public static let vendorID = 0x2972
    /// USB product ID (JadeAudio JA11).
    public static let productID = 0x0102
    /// HID report ID of the EQ command channel, for output and input reports alike.
    public static let reportID: UInt8 = 0x02
    /// Payload bytes in one report on that channel, not counting the report-ID byte.
    public static let payloadLength = 20
}

/// The commands the JA11 can be asked about. All four are read requests; the commands that change
/// the device are `JA11WriteCommand`, a separate type, so that a read request can never carry one.
public enum JA11Command: UInt8, CaseIterable, Sendable {
    case filter = 0x15
    case presetSlot = 0x16
    case preGain = 0x17
    case filterCount = 0x18

    /// Name used in messages, as in "did not answer the pre-gain request".
    public var displayName: String {
        switch self {
        case .filter: "filter"
        case .presetSlot: "preset slot"
        case .preGain: "pre-gain"
        case .filterCount: "filter count"
        }
    }
}

/// The commands that change the JA11. These five are the only ones this library can encode.
public enum JA11WriteCommand: UInt8, CaseIterable, Sendable {
    case filter = 0x15
    case presetSlot = 0x16
    case preGain = 0x17
    case filterCount = 0x18
    case save = 0x19

    /// Number of data bytes a write frame for this command carries, exactly.
    var dataLength: Int {
        switch self {
        case .filter: 8
        case .preGain: 2
        case .presetSlot, .filterCount, .save: 1
        }
    }
}

/// Preset slot numbers as the JA11 reports them.
public enum JA11SlotID {
    public static let vocal: UInt8 = 0
    public static let classic: UInt8 = 1
    public static let bass: UInt8 = 2
    public static let user1: UInt8 = 3
    public static let off: UInt8 = 4
}

/// Limits fixed by the JA11's firmware.
public enum JA11Limits {
    public static let maxBands = 5
    public static let gainRange: ClosedRange<Double> = -12...12
    public static let qRange: ClosedRange<Double> = 0.1...10
    public static let preGainRange: ClosedRange<Double> = -12...12
    public static let frequencyRange: ClosedRange<Int> = 20...20_000
}

/// Values in the units the JA11 uses on the wire.
///
/// Each helper replaces NaN first (a gain by 0.0, Q and frequency by the lower limit), then clamps
/// to the device limit, then scales and rounds to the nearest wire step with ties away from zero.
/// An infinity ends on the limit on its side. Nothing outside the device limits comes out of them.
extension JA11Limits {
    /// A filter gain in tenths of a dB, within -120...120.
    public static func gainTenths(_ dB: Double) -> Int {
        wireUnits(dB, replacingNaNWith: 0.0, in: gainRange, scale: 10)
    }

    /// A pre-gain in tenths of a dB, within -120...120.
    public static func preGainTenths(_ dB: Double) -> Int {
        wireUnits(dB, replacingNaNWith: 0.0, in: preGainRange, scale: 10)
    }

    /// A quality factor in hundredths, within 10...1000.
    public static func qHundredths(_ q: Double) -> Int {
        wireUnits(q, replacingNaNWith: qRange.lowerBound, in: qRange, scale: 100)
    }

    /// A frequency in whole Hz, within 20...20000.
    public static func hertz(_ frequency: Double) -> Int {
        let range = Double(frequencyRange.lowerBound)...Double(frequencyRange.upperBound)
        return wireUnits(frequency, replacingNaNWith: range.lowerBound, in: range, scale: 1)
    }

    private static func wireUnits(
        _ value: Double,
        replacingNaNWith fallback: Double,
        in range: ClosedRange<Double>,
        scale: Double
    ) -> Int {
        let defined = value.isNaN ? fallback : value
        let clamped = min(max(defined, range.lowerBound), range.upperBound)
        return Int((clamped * scale).rounded(.toNearestOrAwayFromZero))
    }
}
