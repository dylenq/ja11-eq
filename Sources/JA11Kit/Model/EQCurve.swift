import Foundation

/// One band of an editable curve.
///
/// Values are free: a band may hold any number. `EQCurve.clamped()` is what brings them inside the
/// device limits before anything is encoded.
public struct EQBand: Sendable, Equatable, Codable {
    public var type: FilterType
    /// Centre or corner frequency in Hz.
    public var frequency: Double
    /// Gain in dB.
    public var gain: Double
    /// Quality factor.
    public var q: Double
    /// A disabled band keeps its values but is sent to the device with 0.0 dB gain.
    public var enabled: Bool

    public init(type: FilterType, frequency: Double, gain: Double, q: Double, enabled: Bool = true) {
        self.type = type
        self.frequency = frequency
        self.gain = gain
        self.q = q
        self.enabled = enabled
    }

    /// Reads a band from a curve file. `enabled` may be left out and then counts as true; every
    /// other key is required. Nothing is clamped here: a file may hold any numbers, and
    /// `EQCurve.clamped()` is what the write path applies before encoding.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(FilterType.self, forKey: .type)
        frequency = try container.decode(Double.self, forKey: .frequency)
        gain = try container.decode(Double.self, forKey: .gain)
        q = try container.decode(Double.self, forKey: .q)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case type, frequency, gain, q, enabled
    }

    /// The band that fills an unused position: peak, 1000 Hz, 0.0 dB, Q 1.0, disabled.
    public static let neutral = EQBand(type: .peak, frequency: 1000, gain: 0.0, q: 1.0, enabled: false)

    /// The band with every value inside the device limits and at wire resolution.
    fileprivate func clamped() -> EQBand {
        EQBand(
            type: type,
            frequency: Double(JA11Limits.hertz(frequency)),
            gain: Double(JA11Limits.gainTenths(gain)) / 10,
            q: Double(JA11Limits.qHundredths(q)) / 100,
            enabled: enabled
        )
    }
}

/// An editable EQ curve: a pre-gain and bands in device order.
///
/// The position of a band in `bands` is its filter index on the device. Bands are never sorted.
public struct EQCurve: Sendable, Equatable, Codable {
    /// Pre-gain in dB.
    public var preGain: Double
    public var bands: [EQBand]

    public init(preGain: Double, bands: [EQBand]) {
        self.preGain = preGain
        self.bands = bands
    }

    /// The curve a device state describes, every band enabled.
    ///
    /// Nil unless the state has exactly five bands and each has a filter type this library knows.
    public init?(state: EQState) {
        guard state.bands.count == JA11Limits.maxBands else { return nil }
        var bands: [EQBand] = []
        for band in state.bands {
            guard let type = band.type else { return nil }
            bands.append(EQBand(type: type, frequency: Double(band.frequency), gain: band.gain, q: band.q))
        }
        self.init(preGain: state.preGain, bands: bands)
    }

    /// The curve as the device can hold it: exactly five bands, every value inside the device
    /// limits and rounded to wire resolution (0.1 dB, 0.01 Q, 1 Hz).
    ///
    /// The first five bands are kept in their order; missing ones are filled with
    /// `EQBand.neutral`. Type and enabled flag are left as they are.
    public func clamped() -> EQCurve {
        var kept = bands.prefix(JA11Limits.maxBands).map { $0.clamped() }
        while kept.count < JA11Limits.maxBands {
            kept.append(.neutral)
        }
        return EQCurve(preGain: Double(JA11Limits.preGainTenths(preGain)) / 10, bands: kept)
    }

    /// What an apply sends: slot 3 (USER1), the clamped pre-gain and five filters numbered by
    /// position. A disabled band goes out with 0.0 dB gain and its type, frequency and Q unchanged.
    public func deviceState() -> EQState {
        let curve = clamped()
        let bands = curve.bands.enumerated().map { index, band in
            Band(
                index: index,
                typeID: band.type.rawValue,
                frequency: Int(band.frequency),
                gain: band.enabled ? band.gain : 0.0,
                q: band.q
            )
        }
        return EQState(slotID: JA11SlotID.user1, preGain: curve.preGain, bands: bands)
    }
}

extension EQCurve {
    /// The built-in test curve.
    public static func testCurve(basedOn original: EQCurve) -> EQCurve {
        original
    }
}

extension FilterType: Codable {
    /// Name in a curve file.
    var codingName: String {
        switch self {
        case .peak: "peak"
        case .lowShelf: "lowShelf"
        case .highShelf: "highShelf"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let type = FilterType.allCases.first(where: { $0.codingName == name }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unknown filter type \"\(name)\"; expected peak, lowShelf or highShelf"
            )
        }
        self = type
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codingName)
    }
}

extension EQState {
    /// How this state, read from the device, differs from the state that was sent.
    ///
    /// Empty when the two are equal at wire resolution: whole tenths of a dB, hundredths of Q and
    /// whole Hz. Both sides are only scaled and rounded, never clamped, so a value the device
    /// reports outside its own limits is a difference and never passes for the nearest limit. A
    /// value that is not finite, on either side, is a difference as well.
    public func differences(from sent: EQState) -> [String] {
        var lines: [String] = []

        if slotID != sent.slotID {
            lines.append("slot: sent \(Self.slotText(sent.slotID)), read \(Self.slotText(slotID))")
        }
        if Self.differ(sent.preGain, preGain, scale: 10) {
            lines.append("pre-gain: sent \(Self.decibelText(sent.preGain)) dB, read \(Self.decibelText(preGain)) dB")
        }
        if bands.count != sent.bands.count {
            lines.append("filters: sent \(sent.bands.count), read \(bands.count)")
        }

        for (position, (was, now)) in zip(sent.bands, bands).enumerated() {
            if was.index != now.index {
                lines.append("filter \(position) index: sent \(was.index), read \(now.index)")
            }
            if was.typeID != now.typeID {
                lines.append("filter \(position) type: sent \(Self.typeText(was)), read \(Self.typeText(now))")
            }
            if was.frequency != now.frequency {
                lines.append("filter \(position) frequency: sent \(was.frequency) Hz, read \(now.frequency) Hz")
            }
            if Self.differ(was.gain, now.gain, scale: 10) {
                lines.append("filter \(position) gain: sent \(Self.decibelText(was.gain)) dB, read \(Self.decibelText(now.gain)) dB")
            }
            if Self.differ(was.q, now.q, scale: 100) {
                lines.append("filter \(position) Q: sent \(Self.qText(was.q)), read \(Self.qText(now.q))")
            }
        }
        return lines
    }

    /// Whether two values differ once each is scaled to wire units and rounded. No clamping.
    private static func differ(_ a: Double, _ b: Double, scale: Double) -> Bool {
        guard a.isFinite, b.isFinite else { return true }
        return (a * scale).rounded(.toNearestOrAwayFromZero) != (b * scale).rounded(.toNearestOrAwayFromZero)
    }

    private static func slotText(_ id: UInt8) -> String {
        "\(id) (\(PresetSlot(rawValue: id)?.displayName ?? "unknown"))"
    }

    private static func typeText(_ band: Band) -> String {
        band.type?.displayName ?? "type-\(band.typeID)"
    }

    private static func decibelText(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private static func qText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
