import Foundation

/// One second-order filter section, by its six coefficients.
public struct Biquad: Sendable, Equatable {
    public let b0: Double
    public let b1: Double
    public let b2: Double
    public let a0: Double
    public let a1: Double
    public let a2: Double

    public static func peaking(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        Biquad(b0: 1, b1: 0, b2: 0, a0: 1, a1: 0, a2: 0)
    }

    public static func lowShelf(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        Biquad(b0: 1, b1: 0, b2: 0, a0: 1, a1: 0, a2: 0)
    }

    public static func highShelf(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        Biquad(b0: 1, b1: 0, b2: 0, a0: 1, a1: 0, a2: 0)
    }

    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        0.0
    }
}

extension EQCurve {
    public static let nominalSampleRate: Double = 96_000

    public static func logGrid(points: Int = 512) -> [Double] {
        []
    }

    public func bandResponse(at frequency: Double) -> Double {
        0.0
    }

    public func response(at frequency: Double) -> Double {
        0.0
    }

    public func autoPreGain() -> Double {
        0.0
    }
}
