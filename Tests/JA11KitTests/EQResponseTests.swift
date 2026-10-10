import Foundation
import Testing
@testable import JA11Kit

/// Response math and auto pre-gain (CONTEXT D-07, D-08). Pure arithmetic: no transport, no device.
@Suite struct EQResponseTests {
    // MARK: - Curves

    static func peak(_ frequency: Double, gain: Double, q: Double = 1.0, enabled: Bool = true) -> EQBand {
        EQBand(type: .peak, frequency: frequency, gain: gain, q: q, enabled: enabled)
    }

    static func curve(_ bands: [EQBand], preGain: Double = 0.0) -> EQCurve {
        EQCurve(preGain: preGain, bands: bands)
    }

    /// Five enabled peak bands at 0.0 dB, pre-gain 0.
    static let flat = curve([100.0, 300, 1000, 3000, 10_000].map { peak($0, gain: 0.0) })
    static let plus6Peak = curve([peak(1000, gain: 6.0)])
    static let minus6Peak = curve([peak(1000, gain: -6.0)])
    static let lowShelfPlus6 = curve([EQBand(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.70)])
    static let highShelfPlus6 = curve([EQBand(type: .highShelf, frequency: 8000, gain: 6.0, q: 0.70)])
    /// The bands of the built-in test curve (D-16).
    static let mixed = curve([
        EQBand(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.70),
        peak(1000, gain: -3.0),
        peak(704, gain: 0.0, q: 1.20),
        peak(7171, gain: 0.0, q: 1.50),
        EQBand(type: .highShelf, frequency: 3973, gain: 0.0, q: 0.40),
    ])
    static let stackedBoosts = curve([EQBand](repeating: peak(1000, gain: 12.0), count: 5))

    static func near(_ value: Double, _ expected: Double, within tolerance: Double) -> Bool {
        abs(value - expected) <= tolerance
    }

    /// The largest band response over the default grid.
    static func largestBoost(of curve: EQCurve) -> Double {
        EQCurve.logGrid().map { curve.bandResponse(at: $0) }.max() ?? 0.0
    }

    /// Whether a value is a whole number of tenths, as far as a Double can tell.
    static func isWholeTenths(_ value: Double) -> Bool {
        abs(value * 10 - (value * 10).rounded()) < 1e-9
    }

    // MARK: - Response (D-07)

    @Test func aFlatCurveIsZeroEverywhere() {
        for frequency in [20.0, 100, 1000, 10_000, 20_000] {
            #expect(Self.near(Self.flat.response(at: frequency), 0.0, within: 1e-9))
        }
    }

    @Test func aPlus6PeakReadsPlus6AtItsCentreAndFallsAwayOnBothSides() {
        #expect(Self.near(Self.plus6Peak.response(at: 1000), 6.0, within: 1e-6))
        #expect(Self.plus6Peak.response(at: 100) < 0.5)
        #expect(Self.plus6Peak.response(at: 10_000) < 0.5)
        #expect(Self.plus6Peak.response(at: 100) > 0.0)
        #expect(Self.near(Self.plus6Peak.response(at: 500), Self.plus6Peak.response(at: 2000), within: 0.2))
        #expect(Self.plus6Peak.response(at: 500) > 0.5)
    }

    @Test func aMinus3PeakReadsMinus3AtItsCentre() {
        #expect(Self.near(Self.curve([Self.peak(1000, gain: -3.0)]).response(at: 1000), -3.0, within: 1e-6))
    }

    @Test func aLowShelfIsHalfItsGainAtTheCornerAndFullGainWellBelow() {
        #expect(Self.near(Self.lowShelfPlus6.response(at: 100), 3.0, within: 1e-6))
        #expect(Self.near(Self.lowShelfPlus6.response(at: 5), 6.0, within: 0.1))
        #expect(Self.near(Self.lowShelfPlus6.response(at: 10_000), 0.0, within: 0.1))
    }

    @Test func aHighShelfIsHalfItsGainAtTheCornerAndFullGainWellAbove() {
        #expect(Self.near(Self.highShelfPlus6.response(at: 8000), 3.0, within: 1e-6))
        #expect(Self.near(Self.highShelfPlus6.response(at: 100), 0.0, within: 0.1))
        #expect(Self.near(Self.highShelfPlus6.response(at: 47_000), 6.0, within: 0.1))
    }

    @Test func aLowShelfCutReachesItsGainWellBelowTheCorner() {
        let cut = Self.curve([EQBand(type: .lowShelf, frequency: 100, gain: -6.0, q: 0.70)])
        #expect(Self.near(cut.response(at: 5), -6.0, within: 0.1))
        #expect(Self.near(cut.response(at: 100), -3.0, within: 1e-6))
    }

    @Test func bandsAdd() {
        let twoPeaks = Self.curve([Self.peak(1000, gain: 3.0), Self.peak(1000, gain: 3.0)])
        #expect(Self.near(twoPeaks.response(at: 1000), 6.0, within: 1e-6))
    }

    @Test func aDisabledBandAddsNothing() {
        let disabled = Self.curve([Self.peak(1000, gain: 6.0, enabled: false)])
        #expect(Self.near(disabled.response(at: 1000), 0.0, within: 1e-9))
        #expect(Self.near(disabled.bandResponse(at: 1000), 0.0, within: 1e-9))
    }

    @Test func responseIncludesPreGainAndBandResponseLeavesItOut() {
        let withPreGain = Self.curve([Self.peak(1000, gain: 6.0)], preGain: -4.0)
        #expect(Self.near(withPreGain.response(at: 1000), withPreGain.bandResponse(at: 1000) - 4.0, within: 1e-9))
        #expect(Self.near(withPreGain.bandResponse(at: 1000), Self.plus6Peak.bandResponse(at: 1000), within: 1e-12))
        #expect(Self.near(withPreGain.response(at: 1000), 2.0, within: 1e-6))
    }

    @Test func outOfRangeValuesAreEvaluatedAsTheyWouldBeSent() {
        #expect(Self.near(Self.curve([Self.peak(1000, gain: 40)]).response(at: 1000), 12.0, within: 1e-6))
        #expect(Self.near(Self.curve([Self.peak(1000, gain: 6.0)], preGain: -40).response(at: 1000), -6.0, within: 1e-6))
    }

    @Test func eachBiquadShapeIsFlatAtZeroGain() {
        let shapes = [
            Biquad.peaking(frequency: 1000, gain: 0, q: 1, sampleRate: 96_000),
            Biquad.lowShelf(frequency: 100, gain: 0, q: 0.7, sampleRate: 96_000),
            Biquad.highShelf(frequency: 8000, gain: 0, q: 0.7, sampleRate: 96_000),
        ]
        for shape in shapes {
            for frequency in [20.0, 1000, 20_000] {
                #expect(Self.near(shape.magnitudeDB(at: frequency, sampleRate: 96_000), 0.0, within: 1e-9))
            }
        }
        #expect(Self.near(
            Biquad.peaking(frequency: 1000, gain: 6, q: 1, sampleRate: 96_000).magnitudeDB(at: 1000, sampleRate: 96_000),
            6.0, within: 1e-6
        ))
    }

    @Test func theNominalSampleRateIs96kHz() {
        #expect(EQCurve.nominalSampleRate == 96_000)
    }

    // MARK: - Grid

    @Test func theLogGridRunsFrom20HzTo20kHzAscending() {
        let grid = EQCurve.logGrid()
        #expect(grid.count == 512)
        #expect(grid.first == 20.0)
        #expect(Self.near(grid.last ?? 0, 20_000.0, within: 1e-6))
        #expect(zip(grid, grid.dropFirst()).allSatisfy { $0 < $1 })
        #expect(EQCurve.logGrid(points: 1024).count == 1024)
    }

    // MARK: - Auto pre-gain (D-08)

    @Test func autoPreGainOffsetsABoost() {
        #expect(Self.plus6Peak.autoPreGain() == -6.0)

        let shelf = Self.lowShelfPlus6.autoPreGain()
        #expect(shelf >= -6.0)
        #expect(shelf <= -5.8)
        #expect(Self.isWholeTenths(shelf))
    }

    @Test func autoPreGainIsPositiveZeroForACutOnlyCurve() {
        let result = Self.minus6Peak.autoPreGain()
        #expect(result == 0.0)
        #expect(result.sign == .plus)
    }

    @Test func autoPreGainForAMixedCurveFollowsItsLargestBoost() {
        let result = Self.mixed.autoPreGain()
        #expect(result >= -6.0)
        #expect(result <= -5.0)
        #expect(Self.isWholeTenths(result))
    }

    @Test func autoPreGainIsClampedToMinus12() {
        #expect(Self.stackedBoosts.autoPreGain() == -12.0)
    }

    @Test func autoPreGainIgnoresTheCurvesOwnPreGainAndItsDisabledBands() {
        #expect(Self.curve([Self.peak(1000, gain: 6.0)], preGain: -9.0).autoPreGain() == -6.0)
        #expect(Self.curve([Self.peak(1000, gain: 6.0)], preGain: 9.0).autoPreGain() == -6.0)
        #expect(Self.curve([Self.peak(1000, gain: 6.0, enabled: false)]).autoPreGain() == 0.0)
        #expect(Self.curve([]).autoPreGain() == 0.0)
        #expect(Self.flat.autoPreGain() == 0.0)
    }

    @Test func autoPreGainRoundsTowardMoreAttenuation() {
        let curves = [
            Self.flat, Self.plus6Peak, Self.minus6Peak, Self.lowShelfPlus6, Self.highShelfPlus6, Self.mixed,
            Self.curve([Self.peak(1000, gain: 3.14, q: 4.0), Self.peak(3000, gain: 2.72, q: 0.5)]),
        ]
        for curve in curves {
            let result = curve.autoPreGain()
            #expect((-12.0...0.0).contains(result))
            #expect(Self.isWholeTenths(result))
            // With the pre-gain applied, the largest boost on the grid does not exceed 0 dB,
            // and no more than one wire step is given away.
            #expect(result + Self.largestBoost(of: curve) <= 1e-9)
            #expect(result + max(0, Self.largestBoost(of: curve)) > -0.1 - 1e-9)
        }
        // Beyond the clamp the boost cannot be offset in full.
        #expect(Self.stackedBoosts.autoPreGain() + Self.largestBoost(of: Self.stackedBoosts) > 0)
    }
}
