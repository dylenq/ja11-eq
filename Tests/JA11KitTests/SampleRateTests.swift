import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

/// A sample-rate source the test feeds by hand. Later plans reuse it.
final class FakeSampleRates: OutputSampleRateSource, @unchecked Sendable {
    private let stream: AsyncStream<Double?>
    private let continuation: AsyncStream<Double?>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Double?.self)
    }

    func rates() -> AsyncStream<Double?> { stream }
    func feed(_ value: Double?) { continuation.yield(value) }
}

@Suite struct SampleRateTests {
    @Test func bandEdges() {
        let cases: [(Double, String)] = [
            (44100, "44.1 kHz"), (48000, "48 kHz"), (88200, "88.2 kHz"), (96000, "96 kHz"),
            (176400, "176.4 kHz"), (192000, "192 kHz"), (352800, "352.8 kHz"), (384000, "384 kHz"),
            (705600, "705.6 kHz"), (768000, "768 kHz"),
        ]
        for (hertz, text) in cases {
            #expect(SampleRateFormat.text(hertz) == text)
        }
    }

    @Test func roundingHalfAwayFromZero() {
        #expect(SampleRateFormat.text(44099.9) == "44.1 kHz")
        #expect(SampleRateFormat.text(44149.0) == "44.1 kHz")
        #expect(SampleRateFormat.text(44150.0) == "44.2 kHz")
        #expect(SampleRateFormat.text(999.0) == "1 kHz")
        #expect(SampleRateFormat.text(1.0) == "0 kHz")
    }

    @Test func invalidValuesGiveEmDash() {
        let dash = "\u{2014}"
        for value in [0.0, -48000, .nan, .infinity, -.infinity] {
            #expect(SampleRateFormat.text(value) == dash)
        }
        #expect(SampleRateFormat.text(nil) == dash)
    }

    @Test func textIgnoresLocale() {
        // The formatter does no locale work; a decimal-comma process locale cannot change it.
        #expect(SampleRateFormat.text(352800) == "352.8 kHz")
        #expect(!SampleRateFormat.text(352800).contains(","))
    }

    @Test func coreAudioReadIsNilOrPositive() {
        let rate = CoreAudioSampleRate().currentRate()
        if let rate { #expect(rate.isFinite && rate > 0) }
        #expect(CoreAudioSampleRate.deviceName == "JadeAudio JA11")
    }

    @MainActor
    @Test func modelShowsRatesFromSource() async throws {
        let dongle = FakeDongle()
        let source = FakeSampleRates()
        let model = try await AppModelFixture.make(dongle: dongle, connected: false, sampleRates: source)
        #expect(model.sampleRateText == "\u{2014}")

        source.feed(352800)
        await waitUntil("352.8") { model.sampleRateText == "352.8 kHz" }
        source.feed(48000)
        await waitUntil("48") { model.sampleRateText == "48 kHz" }
        source.feed(nil)
        await waitUntil("dash") { model.sampleRateText == "\u{2014}" }
        model.stop()
    }
}
