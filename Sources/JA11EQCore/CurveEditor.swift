import Foundation
import JA11Kit

/// The curve the user edits: five bands and a pre-gain, always inside the device limits.
///
/// Every operation replaces the curve by `clamped()`, so the editor never holds a value the dongle
/// could not store. Bands keep their positions (their filter indices); nothing is sorted or merged.
/// While `isEditable` is false every operation is ignored. Nothing here talks to the device.
public struct CurveEditor: Equatable, Sendable {
    /// The edited curve; always clamped.
    public private(set) var curve: EQCurve
    /// The curve last read from, or applied to, the DAC.
    public private(set) var baseline: EQCurve
    /// When on, pre-gain follows `EQCurve.autoPreGain()` after every edit.
    public private(set) var autoPreGain: Bool
    public private(set) var isEditable: Bool

    private static let bandRange = 0..<JA11Limits.maxBands

    /// Five neutral, disabled bands, pre-gain 0, not editable.
    public static let empty: CurveEditor = {
        let curve = EQCurve(preGain: 0.0, bands: Array(repeating: .neutral, count: JA11Limits.maxBands)).clamped()
        return CurveEditor(curve: curve, baseline: curve, autoPreGain: true, isEditable: false)
    }()

    private init(curve: EQCurve, baseline: EQCurve, autoPreGain: Bool, isEditable: Bool) {
        self.curve = curve
        self.baseline = baseline
        self.autoPreGain = autoPreGain
        self.isEditable = isEditable
    }

    /// True exactly when the edited curve differs from the baseline.
    public var isDirty: Bool { curve != baseline }

    /// Replaces curve and baseline with what the DAC holds. Auto starts on only when the loaded
    /// pre-gain equals what Auto would compute.
    public mutating func load(_ newCurve: EQCurve, editable: Bool) {
        let clamped = newCurve.clamped()
        curve = clamped
        baseline = clamped
        isEditable = editable
        autoPreGain = clamped.preGain == clamped.autoPreGain()
    }

    /// The curve now counts as what the DAC holds.
    public mutating func markApplied() {
        guard isEditable else { return }
        baseline = curve
    }

    /// Back to the baseline.
    public mutating func revert() {
        guard isEditable else { return }
        curve = baseline
    }

    public mutating func setEnabled(_ on: Bool, band: Int) {
        edit(band) { $0.enabled = on }
    }

    public mutating func setType(_ type: FilterType, band: Int) {
        edit(band) { $0.type = type }
    }

    public mutating func setFrequency(_ hertz: Double, band: Int) {
        edit(band) { $0.frequency = hertz }
    }

    public mutating func setGain(_ dB: Double, band: Int) {
        edit(band) { $0.gain = dB }
    }

    public mutating func setQ(_ q: Double, band: Int) {
        edit(band) { $0.q = q }
    }

    /// Ignored while Auto is on.
    public mutating func setPreGain(_ dB: Double) {
        guard isEditable, !autoPreGain else { return }
        curve.preGain = dB
        curve = curve.clamped()
    }

    public mutating func setAutoPreGain(_ on: Bool) {
        guard isEditable else { return }
        autoPreGain = on
        applyAuto()
    }

    /// Sets frequency and gain together (a handle drag).
    public mutating func moveBand(_ band: Int, frequency: Double, gain: Double) {
        edit(band) {
            $0.frequency = frequency
            $0.gain = gain
        }
    }

    /// Multiplies the band's Q by `factor`, clamped to the device range.
    public mutating func scaleQ(band: Int, by factor: Double) {
        edit(band) { $0.q *= factor }
    }

    private mutating func edit(_ band: Int, _ change: (inout EQBand) -> Void) {
        guard isEditable, Self.bandRange.contains(band), band < curve.bands.count else { return }
        change(&curve.bands[band])
        curve = curve.clamped()
        applyAuto()
    }

    private mutating func applyAuto() {
        guard autoPreGain else { return }
        curve.preGain = curve.autoPreGain()
        curve = curve.clamped()
    }
}
