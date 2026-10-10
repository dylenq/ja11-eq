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

/// The commands this phase may ask the JA11 about. All four are read requests.
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
