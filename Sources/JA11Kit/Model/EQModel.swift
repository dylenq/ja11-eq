import Foundation

/// A preset slot of the JA11, by the number the device reports.
public enum PresetSlot: UInt8, CaseIterable, Sendable {
    case vocal = 0
    case classic = 1
    case bass = 2
    case user1 = 3
    case off = 4

    /// Name shown to the user.
    public var displayName: String {
        switch self {
        case .vocal: "Vocal"
        case .classic: "Classic"
        case .bass: "Bass"
        case .user1: "USER1"
        case .off: "Off"
        }
    }
}

/// A filter shape the JA11 offers, by the number the device reports.
public enum FilterType: UInt8, CaseIterable, Sendable {
    case peak = 0
    case lowShelf = 1
    case highShelf = 2

    /// Name shown to the user.
    public var displayName: String {
        switch self {
        case .peak: "peak"
        case .lowShelf: "low-shelf"
        case .highShelf: "high-shelf"
        }
    }
}

/// One filter of the JA11's equalizer, as read from the device.
public struct Band: Sendable, Equatable {
    /// Position of the filter on the device, from 0.
    public var index: Int
    /// Filter type number exactly as the device sent it.
    public var typeID: UInt8
    /// Centre or corner frequency in Hz.
    public var frequency: Int
    /// Gain in dB.
    public var gain: Double
    /// Quality factor.
    public var q: Double

    /// The filter type, or nil when the device sent a number this table does not know.
    public var type: FilterType? {
        FilterType(rawValue: typeID)
    }

    public init(index: Int, typeID: UInt8, frequency: Int, gain: Double, q: Double) {
        self.index = index
        self.typeID = typeID
        self.frequency = frequency
        self.gain = gain
        self.q = q
    }
}

/// The JA11's equalizer state, as read from the device.
public struct EQState: Sendable, Equatable {
    /// Active preset slot number exactly as the device sent it.
    public var slotID: UInt8
    /// Pre-gain in dB.
    public var preGain: Double
    /// The filters, in index order.
    public var bands: [Band]

    /// The active preset slot, or nil when the device sent a number this table does not know.
    public var slot: PresetSlot? {
        PresetSlot(rawValue: slotID)
    }

    public init(slotID: UInt8, preGain: Double, bands: [Band]) {
        self.slotID = slotID
        self.preGain = preGain
        self.bands = bands
    }

    /// The state as the lines `ja11-probe` prints.
    ///
    /// A slot or filter type the tables do not know stays visible as its number. Numbers are
    /// formatted without a locale, so the decimal separator is always a dot.
    public func reportLines() -> [String] {
        var lines = [
            "slot: \(slotID) (\(slot?.displayName ?? "unknown"))",
            "pre-gain: \(Self.decibels(preGain)) dB",
            "filters: \(bands.count)",
        ]
        for band in bands {
            let type = band.type?.displayName ?? "type-\(band.typeID)"
            let q = String(format: "%.2f", band.q)
            lines.append("filter \(band.index): \(type) \(band.frequency) Hz \(Self.decibels(band.gain)) dB Q \(q)")
        }
        return lines
    }

    /// A gain with its sign and one decimal: `+6.0`, `-3.5`, `+0.0`.
    private static func decibels(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }
}
