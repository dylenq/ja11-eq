import Foundation
import Testing
@testable import JA11Kit

/// The curve model: clamping, rounding, padding, ordering, read-back comparison and JSON
/// (CONTEXT D-05, D-06, D-10). No transport of any kind is created here.
@Suite struct EQCurveTests {
    // MARK: - Helpers

    static func peak(_ frequency: Double = 1000, gain: Double = 0.0, q: Double = 1.0, enabled: Bool = true) -> EQBand {
        EQBand(type: .peak, frequency: frequency, gain: gain, q: q, enabled: enabled)
    }

    /// One band after `clamped()`.
    static func clamped(_ band: EQBand) -> EQBand {
        EQCurve(preGain: 0, bands: [band]).clamped().bands[0]
    }

    static func clampedPreGain(_ preGain: Double) -> Double {
        EQCurve(preGain: preGain, bands: []).clamped().preGain
    }

    /// The state the dongle held when Phase 1 read it.
    static let original = EQState(slotID: 3, preGain: 0.0, bands: FakeDongle.originalBands)

    /// A state that was sent, and the same state with one change as the device might report it.
    static let sent = EQState(
        slotID: 3,
        preGain: -6.0,
        bands: [
            Band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70),
            Band(index: 1, typeID: 0, frequency: 1000, gain: -3.0, q: 1.00),
            Band(index: 2, typeID: 0, frequency: 704, gain: 0.0, q: 1.20),
            Band(index: 3, typeID: 0, frequency: 7171, gain: 0.0, q: 1.50),
            Band(index: 4, typeID: 2, frequency: 3973, gain: 0.0, q: 0.40),
        ]
    )

    static func read(_ change: (inout EQState) -> Void) -> EQState {
        var state = sent
        change(&state)
        return state
    }

    /// The differences between a sent state and a read state that differ in filter 0 only.
    static func filter0Differences(sent: (inout Band) -> Void, read: (inout Band) -> Void) -> [String] {
        var was = Self.sent
        var now = Self.sent
        sent(&was.bands[0])
        read(&now.bands[0])
        return now.differences(from: was)
    }

    // MARK: - Clamping to the device limits (D-05)

    @Test func gainOutOfRangeClampsToTheLimit() {
        #expect(Self.clamped(Self.peak(gain: 15)).gain == 12.0)
        #expect(Self.clamped(Self.peak(gain: -15)).gain == -12.0)
    }

    @Test func qOutOfRangeClampsToTheLimit() {
        #expect(Self.clamped(Self.peak(q: 0.01)).q == 0.1)
        #expect(Self.clamped(Self.peak(q: 25)).q == 10.0)
    }

    @Test func frequencyOutOfRangeClampsToTheLimit() {
        #expect(Self.clamped(Self.peak(5)).frequency == 20)
        #expect(Self.clamped(Self.peak(30_000)).frequency == 20_000)
    }

    @Test func preGainOutOfRangeClampsToTheLimit() {
        #expect(Self.clampedPreGain(13) == 12.0)
        #expect(Self.clampedPreGain(-13) == -12.0)
    }

    @Test func aValueExactlyOnALimitIsKept() {
        #expect(Self.clamped(Self.peak(gain: 12.0)).gain == 12.0)
        #expect(Self.clamped(Self.peak(gain: -12.0)).gain == -12.0)
        #expect(Self.clamped(Self.peak(q: 0.1)).q == 0.1)
        #expect(Self.clamped(Self.peak(q: 10.0)).q == 10.0)
        #expect(Self.clamped(Self.peak(20)).frequency == 20)
        #expect(Self.clamped(Self.peak(20_000)).frequency == 20_000)
        #expect(Self.clampedPreGain(12.0) == 12.0)
        #expect(Self.clampedPreGain(-12.0) == -12.0)
    }

    @Test func aValueOneWireStepOutsideMovesOntoTheLimit() {
        #expect(Self.clamped(Self.peak(gain: 12.1)).gain == 12.0)
        #expect(Self.clamped(Self.peak(gain: -12.1)).gain == -12.0)
        #expect(Self.clamped(Self.peak(q: 0.09)).q == 0.1)
        #expect(Self.clamped(Self.peak(q: 10.01)).q == 10.0)
        #expect(Self.clamped(Self.peak(19)).frequency == 20)
        #expect(Self.clamped(Self.peak(20_001)).frequency == 20_000)
    }

    @Test func valuesRoundToWireResolutionWithTiesAwayFromZero() {
        #expect(Self.clamped(Self.peak(gain: 6.04)).gain == 6.0)
        #expect(Self.clamped(Self.peak(gain: 6.06)).gain == 6.1)
        #expect(Self.clamped(Self.peak(gain: 0.25)).gain == 0.3)
        #expect(Self.clamped(Self.peak(gain: -0.25)).gain == -0.3)
        #expect(Self.clamped(Self.peak(q: 0.125)).q == 0.13)
        #expect(Self.clamped(Self.peak(100.5)).frequency == 101)
        #expect(Self.clamped(Self.peak(100.4)).frequency == 100)
    }

    @Test func notANumberBecomesNeutralOrTheLowerLimit() {
        #expect(Self.clamped(Self.peak(gain: .nan)).gain == 0.0)
        #expect(Self.clampedPreGain(.nan) == 0.0)
        #expect(Self.clamped(Self.peak(q: .nan)).q == 0.1)
        #expect(Self.clamped(Self.peak(.nan)).frequency == 20)
    }

    @Test func infinityEndsOnTheLimitOnItsSide() {
        #expect(Self.clamped(Self.peak(gain: .infinity)).gain == 12.0)
        #expect(Self.clamped(Self.peak(gain: -.infinity)).gain == -12.0)
        #expect(Self.clamped(Self.peak(q: .infinity)).q == 10.0)
        #expect(Self.clamped(Self.peak(q: -.infinity)).q == 0.1)
        #expect(Self.clamped(Self.peak(.infinity)).frequency == 20_000)
        #expect(Self.clamped(Self.peak(-.infinity)).frequency == 20)
        #expect(Self.clampedPreGain(.infinity) == 12.0)
        #expect(Self.clampedPreGain(-.infinity) == -12.0)
    }

    @Test func clampingTwiceEqualsClampingOnce() {
        let curve = EQCurve(
            preGain: -13.37,
            bands: [
                EQBand(type: .lowShelf, frequency: 59.6, gain: 6.06, q: 0.705),
                Self.peak(30_000, gain: -40, q: 0.001),
                Self.peak(.nan, gain: .nan, q: .nan, enabled: false),
            ]
        )
        #expect(curve.clamped().clamped() == curve.clamped())
    }

    // MARK: - Band count and order (D-05, D-06)

    @Test func aCurveWithNoBandsIsFilledWithFiveNeutralBands() {
        let curve = EQCurve(preGain: 0, bands: []).clamped()
        #expect(curve.bands == [EQBand](repeating: .neutral, count: 5))
        #expect(EQBand.neutral == EQBand(type: .peak, frequency: 1000, gain: 0.0, q: 1.0, enabled: false))
    }

    @Test func twoBandsAreKeptAndFollowedByThreeNeutralBands() {
        let first = EQBand(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.7)
        let second = Self.peak(1000, gain: -3.0)
        let curve = EQCurve(preGain: 0, bands: [first, second]).clamped()
        #expect(curve.bands == [first, second, .neutral, .neutral, .neutral])
    }

    @Test func sevenBandsKeepTheirFirstFiveInOrder() {
        let bands = [100.0, 200, 300, 400, 500, 600, 700].map { Self.peak($0, gain: 1.0) }
        let curve = EQCurve(preGain: 0, bands: bands).clamped()
        #expect(curve.bands.map(\.frequency) == [100, 200, 300, 400, 500])
    }

    @Test func bandsAreNeverSortedAndAreNumberedByPosition() {
        let bands = [8000.0, 4000, 1000, 250, 60].map { Self.peak($0, gain: 2.0) }
        let curve = EQCurve(preGain: 0, bands: bands)
        #expect(curve.clamped().bands.map(\.frequency) == [8000, 4000, 1000, 250, 60])

        let state = curve.deviceState()
        #expect(state.bands.map(\.index) == [0, 1, 2, 3, 4])
        #expect(state.bands.map(\.frequency) == [8000, 4000, 1000, 250, 60])
    }

    @Test func twoIdenticalBandsStayTwoBandsUnderTheirOwnIndices() {
        let twin = Self.peak(1000, gain: 3.0, q: 2.0)
        let state = EQCurve(preGain: 0, bands: [twin, twin]).deviceState()
        #expect(state.bands[0] == Band(index: 0, typeID: 0, frequency: 1000, gain: 3.0, q: 2.0))
        #expect(state.bands[1] == Band(index: 1, typeID: 0, frequency: 1000, gain: 3.0, q: 2.0))
    }

    @Test func aDisabledBandKeepsItsValuesAndIsSentWithZeroGain() {
        let band = EQBand(type: .highShelf, frequency: 8000, gain: 6.0, q: 0.7, enabled: false)
        let curve = EQCurve(preGain: 0, bands: [band])

        #expect(curve.clamped().bands[0] == band)
        #expect(curve.deviceState().bands[0] == Band(index: 0, typeID: 2, frequency: 8000, gain: 0.0, q: 0.7))
    }

    @Test func deviceStateIsAlwaysSlot3WithFiveBands() {
        let inputs = [
            EQCurve(preGain: 0, bands: []),
            EQCurve(preGain: 99, bands: [Self.peak()]),
            EQCurve(preGain: -99, bands: [EQBand](repeating: Self.peak(gain: 50), count: 9)),
        ]
        for curve in inputs {
            let state = curve.deviceState()
            #expect(state.slotID == 3)
            #expect(state.bands.count == 5)
            #expect(JA11Limits.preGainRange.contains(state.preGain))
            #expect(state.bands.allSatisfy { JA11Limits.gainRange.contains($0.gain) })
        }
    }

    // MARK: - From a device state

    @Test func aCurveFromTheDonglesCurrentContentsHasFiveEnabledBandsWithThoseValues() throws {
        let curve = try #require(EQCurve(state: Self.original))
        #expect(curve.preGain == 0.0)
        #expect(curve.bands == [
            EQBand(type: .lowShelf, frequency: 59, gain: 0.0, q: 0.70),
            EQBand(type: .peak, frequency: 181, gain: 0.0, q: 0.62),
            EQBand(type: .peak, frequency: 704, gain: 0.0, q: 1.20),
            EQBand(type: .peak, frequency: 7171, gain: 0.0, q: 1.50),
            EQBand(type: .highShelf, frequency: 3973, gain: 0.0, q: 0.40),
        ])
        #expect(curve.bands.allSatisfy { $0.enabled })
        // Written back unchanged, it is the state it came from.
        #expect(curve.deviceState() == Self.original)
    }

    @Test func aStateWithFourBandsOrAnUnknownTypeGivesNoCurve() {
        var four = Self.original
        four.bands.removeLast()
        #expect(EQCurve(state: four) == nil)

        var unknown = Self.original
        unknown.bands[2].typeID = 7
        #expect(EQCurve(state: unknown) == nil)
    }

    // MARK: - Read-back comparison (D-10)

    @Test func equalStatesHaveNoDifferences() {
        #expect(Self.sent.differences(from: Self.sent).isEmpty)
    }

    @Test func aDifferenceInOneGainGivesExactlyThatLine() {
        let read = Self.read { $0.bands[1].gain = 0.0 }
        #expect(read.differences(from: Self.sent) == ["filter 1 gain: sent -3.0 dB, read +0.0 dB"])
    }

    @Test func aDifferenceBelowWireResolutionIsNoDifference() {
        let read = Self.read {
            $0.bands[0].q = 0.7000001
            $0.bands[0].gain = 6.0000001
            $0.preGain = -6.0000001
        }
        #expect(read.differences(from: Self.sent).isEmpty)
    }

    @Test func slotCountTypeFrequencyAndQDifferencesAreWorded() {
        #expect(Self.read { $0.slotID = 0 }.differences(from: Self.sent) == ["slot: sent 3 (USER1), read 0 (Vocal)"])
        #expect(Self.read { $0.bands.removeLast() }.differences(from: Self.sent) == ["filters: sent 5, read 4"])
        #expect(Self.read { $0.preGain = 0.0 }.differences(from: Self.sent) == ["pre-gain: sent -6.0 dB, read +0.0 dB"])
        #expect(Self.read { $0.bands[1].typeID = 1 }.differences(from: Self.sent) == ["filter 1 type: sent peak, read low-shelf"])
        #expect(Self.read { $0.bands[1].frequency = 999 }.differences(from: Self.sent) == ["filter 1 frequency: sent 1000 Hz, read 999 Hz"])
        #expect(Self.read { $0.bands[1].q = 0.99 }.differences(from: Self.sent) == ["filter 1 Q: sent 1.00, read 0.99"])
    }

    @Test func differencesComeInAFixedOrder() {
        let read = Self.read {
            $0.bands[1].q = 0.99
            $0.bands[0].gain = 0.0
            $0.preGain = 0.0
            $0.slotID = 0
        }
        #expect(read.differences(from: Self.sent) == [
            "slot: sent 3 (USER1), read 0 (Vocal)",
            "pre-gain: sent -6.0 dB, read +0.0 dB",
            "filter 0 gain: sent +6.0 dB, read +0.0 dB",
            "filter 1 Q: sent 1.00, read 0.99",
        ])
    }

    @Test func aGainReadBackOutsideTheDeviceLimitsIsADifference() {
        #expect(Self.filter0Differences(sent: { $0.gain = 12.0 }, read: { $0.gain = 13.5 })
            == ["filter 0 gain: sent +12.0 dB, read +13.5 dB"])
        #expect(!Self.filter0Differences(sent: { $0.gain = -12.0 }, read: { $0.gain = -12.1 }).isEmpty)
    }

    @Test func aQReadBackOutsideTheDeviceLimitsIsADifference() {
        #expect(Self.filter0Differences(sent: { $0.q = 0.10 }, read: { $0.q = 0.00 })
            == ["filter 0 Q: sent 0.10, read 0.00"])
        #expect(!Self.filter0Differences(sent: { $0.q = 10.00 }, read: { $0.q = 10.01 }).isEmpty)
    }

    @Test func aFrequencyReadBackOutsideTheDeviceLimitsIsADifference() {
        #expect(Self.filter0Differences(sent: { $0.frequency = 20 }, read: { $0.frequency = 0 })
            == ["filter 0 frequency: sent 20 Hz, read 0 Hz"])
        #expect(!Self.filter0Differences(sent: { $0.frequency = 20_000 }, read: { $0.frequency = 20_001 }).isEmpty)
    }

    @Test func aPreGainReadBackOutsideTheDeviceLimitsIsADifference() {
        var was = Self.sent
        was.preGain = 12.0
        var now = was
        now.preGain = 12.1
        #expect(!now.differences(from: was).isEmpty)

        was.preGain = -12.0
        now.preGain = -20.0
        #expect(now.differences(from: was) == ["pre-gain: sent -12.0 dB, read -20.0 dB"])
    }

    @Test func aValueThatIsNotFiniteIsADifferenceOnEitherSide() {
        #expect(!Self.read { $0.preGain = .nan }.differences(from: Self.sent).isEmpty)
        #expect(!Self.read { $0.bands[0].gain = .infinity }.differences(from: Self.sent).isEmpty)
        let nanSent = Self.read { $0.bands[0].q = .nan }
        #expect(!nanSent.differences(from: nanSent).isEmpty)
    }

    // MARK: - JSON

    static let json = """
        {
          "preGain": -6,
          "bands": [
            { "type": "lowShelf", "frequency": 100, "gain": 6, "q": 0.7, "enabled": true },
            { "type": "peak", "frequency": 1000, "gain": -3, "q": 1 },
            { "type": "highShelf", "frequency": 8000, "gain": 2.5, "q": 0.7, "enabled": false }
          ]
        }
        """

    static func decode(_ text: String) -> EQCurve? {
        try? JSONDecoder().decode(EQCurve.self, from: Data(text.utf8))
    }

    @Test func aCurveSurvivesEncodingAndDecodingUnchanged() throws {
        let curve = EQCurve(
            preGain: -4.5,
            bands: [
                EQBand(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.7),
                EQBand(type: .peak, frequency: 1000, gain: -3.0, q: 1.41, enabled: false),
                EQBand(type: .highShelf, frequency: 8000, gain: 2.5, q: 0.5),
            ]
        )
        let data = try JSONEncoder().encode(curve)
        #expect(try JSONDecoder().decode(EQCurve.self, from: data) == curve)
    }

    @Test func aBandWithoutTheEnabledKeyDecodesAsEnabled() {
        let curve = Self.decode(Self.json)
        #expect(curve?.bands.count == 3)
        #expect(curve?.bands.map(\.enabled) == [true, true, false])
        #expect(curve?.bands[1] == EQBand(type: .peak, frequency: 1000, gain: -3, q: 1, enabled: true))
        #expect(curve?.preGain == -6)
    }

    @Test func filterTypesAreWrittenByName() throws {
        let curve = EQCurve(
            preGain: 0,
            bands: [FilterType.peak, .lowShelf, .highShelf].map { EQBand(type: $0, frequency: 1000, gain: 0, q: 1) }
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(curve)) as? [String: Any]
        let bands = try #require(object?["bands"] as? [[String: Any]])

        #expect(bands.map { $0["type"] as? String } == ["peak", "lowShelf", "highShelf"])
        #expect(Set(bands[0].keys) == ["type", "frequency", "gain", "q", "enabled"])
        #expect(Set((object ?? [:]).keys) == ["preGain", "bands"])
    }

    @Test func decodingDoesNotClamp() {
        let curve = Self.decode(#"{"preGain": 40, "bands": [{"type": "peak", "frequency": 5, "gain": -99, "q": 0}]}"#)
        #expect(curve?.preGain == 40)
        #expect(curve?.bands.first == EQBand(type: .peak, frequency: 5, gain: -99, q: 0))
    }

    @Test func malformedCurvesFailToDecode() {
        // Each of these is the valid one-band curve with one fault.
        #expect(Self.decode(#"{"preGain": 0, "bands": [{"type": "peak", "frequency": 1000, "gain": 0, "q": 1}]}"#) != nil)
        #expect(Self.decode(#"{"preGain": 0, "bands": [{"type": "notch", "frequency": 1000, "gain": 0, "q": 1}]}"#) == nil)
        #expect(Self.decode(#"{"preGain": 0}"#) == nil)
        #expect(Self.decode(#"{"bands": [{"type": "peak", "frequency": 1000, "gain": 0, "q": 1}]}"#) == nil)
        #expect(Self.decode(#"{"preGain": 0, "bands": [{"type": "peak", "frequency": 1000, "q": 1}]}"#) == nil)
        #expect(Self.decode(#"{"preGain": 0, "bands": [{"type": 0, "frequency": 1000, "gain": 0, "q": 1}]}"#) == nil)
    }
}
