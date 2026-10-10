import Foundation

/// One second-order filter section, by its six coefficients.
///
/// The three shapes follow the RBJ Audio EQ Cookbook. For all of them A = 10^(gain / 40),
/// w0 = 2π · frequency / sampleRate and alpha = sin(w0) / (2 Q): the slope of a shelf is expressed
/// through Q, as the JA11 does.
public struct Biquad: Sendable, Equatable {
    public let b0: Double
    public let b1: Double
    public let b2: Double
    public let a0: Double
    public let a1: Double
    public let a2: Double

    /// A bell: `gain` dB at `frequency`, back to 0 dB on both sides.
    public static func peaking(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        let (a, c, alpha) = terms(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        return Biquad(
            b0: 1 + alpha * a,
            b1: -2 * c,
            b2: 1 - alpha * a,
            a0: 1 + alpha / a,
            a1: -2 * c,
            a2: 1 - alpha / a
        )
    }

    /// A low shelf: `gain` dB well below `frequency`, half of it at `frequency`, 0 dB well above.
    public static func lowShelf(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        let (a, c, alpha) = terms(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        let s = 2 * a.squareRoot() * alpha
        return Biquad(
            b0: a * ((a + 1) - (a - 1) * c + s),
            b1: 2 * a * ((a - 1) - (a + 1) * c),
            b2: a * ((a + 1) - (a - 1) * c - s),
            a0: (a + 1) + (a - 1) * c + s,
            a1: -2 * ((a - 1) + (a + 1) * c),
            a2: (a + 1) + (a - 1) * c - s
        )
    }

    /// A high shelf: `gain` dB well above `frequency`, half of it at `frequency`, 0 dB well below.
    public static func highShelf(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        let (a, c, alpha) = terms(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        let s = 2 * a.squareRoot() * alpha
        return Biquad(
            b0: a * ((a + 1) + (a - 1) * c + s),
            b1: -2 * a * ((a - 1) + (a + 1) * c),
            b2: a * ((a + 1) + (a - 1) * c - s),
            a0: (a + 1) - (a - 1) * c + s,
            a1: 2 * ((a - 1) - (a + 1) * c),
            a2: (a + 1) - (a - 1) * c - s
        )
    }

    /// The filter's gain in dB at `frequency`.
    ///
    /// The squared magnitude on the unit circle, worked out without complex numbers. For
    /// coefficients c0, c1, c2 it is c0² + c1² + c2² + 2 (c0 c1 + c1 c2) cos(w) + 2 c0 c2 cos(2w).
    /// That sum is evaluated here in terms of p = sin²(w / 2) — the same value, since
    /// cos(w) = 1 - 2p — because the cosine form subtracts nearly equal numbers at low
    /// frequencies and loses about seven digits there.
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let half = sin(Double.pi * frequency / sampleRate)
        let p = half * half
        let numerator = Self.squaredMagnitude(b0, b1, b2, p)
        let denominator = Self.squaredMagnitude(a0, a1, a2, p)
        return 10 * log10(numerator / denominator)
    }

    private static func squaredMagnitude(_ c0: Double, _ c1: Double, _ c2: Double, _ p: Double) -> Double {
        let sum = c0 + c1 + c2
        return sum * sum - 4 * p * (c0 * c1 + c1 * c2 + 4 * c0 * c2) + 16 * c0 * c2 * p * p
    }

    /// A, cos(w0) and alpha for a filter.
    private static func terms(
        frequency: Double, gain: Double, q: Double, sampleRate: Double
    ) -> (a: Double, cosine: Double, alpha: Double) {
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        return (a, cos(w0), sin(w0) / (2 * q))
    }
}

extension EQCurve {
    /// The sample rate the response is worked out at. A display value: the DAC's own filters run
    /// at whatever rate it is playing.
    public static let nominalSampleRate: Double = 96_000

    /// `points` frequencies from 20 Hz to 20 kHz, both included, evenly spaced in the logarithm.
    public static func logGrid(points: Int = 512) -> [Double] {
        precondition(points >= 2, "a grid needs at least 2 points")
        let low = 20.0
        let high = 20_000.0
        let ratio = high / low
        return (0..<points).map { low * pow(ratio, Double($0) / Double(points - 1)) }
    }

    /// The combined gain in dB of the enabled bands at `frequency`, without the pre-gain.
    ///
    /// The curve is clamped first, so this is the response of what would be sent to the device.
    public func bandResponse(at frequency: Double) -> Double {
        clamped().bands.reduce(0.0) { sum, band in
            guard band.enabled else { return sum }
            return sum + band.biquad().magnitudeDB(at: frequency, sampleRate: Self.nominalSampleRate)
        }
    }

    /// The combined gain in dB at `frequency`: the enabled bands plus the pre-gain.
    public func response(at frequency: Double) -> Double {
        bandResponse(at: frequency) + clamped().preGain
    }

    /// The pre-gain that offsets the curve's largest boost, within -12...0 dB.
    ///
    /// Minus the largest band response over `logGrid()`, never above 0, rounded down to a tenth of
    /// a dB — toward more attenuation. It depends on the bands only; the curve's own pre-gain
    /// plays no part.
    public func autoPreGain() -> Double {
        let clampedCurve = clamped()
        let largest = Self.logGrid().map { clampedCurve.bandResponse(at: $0) }.max() ?? 0.0
        let offset = -max(largest, 0.0)
        // The small term keeps floating-point noise from costing a whole tenth.
        let roundedDown = (offset * 10 + 1e-9).rounded(.down) / 10
        let result = min(max(roundedDown, -12.0), 0.0)
        return result == 0 ? 0.0 : result
    }
}

extension EQBand {
    /// The filter section for this band at the nominal sample rate.
    fileprivate func biquad() -> Biquad {
        let rate = EQCurve.nominalSampleRate
        switch type {
        case .peak: return .peaking(frequency: frequency, gain: gain, q: q, sampleRate: rate)
        case .lowShelf: return .lowShelf(frequency: frequency, gain: gain, q: q, sampleRate: rate)
        case .highShelf: return .highShelf(frequency: frequency, gain: gain, q: q, sampleRate: rate)
        }
    }
}
