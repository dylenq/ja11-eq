import Foundation
import JA11Kit

/// A point in plot coordinates: origin top-left, y grows downward.
public struct GraphPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The frequency-response graph's coordinate maths, free of any window: a logarithmic frequency
/// axis over 20 Hz-20 kHz and a linear gain axis over +-15 dB, mapped onto a `width` x `height`
/// plot. A plot with zero width or height maps everything to 0 and yields no points.
public struct GraphGeometry: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public static let frequencyRange: ClosedRange<Double> = 20...20_000
    public static let decibelRange: ClosedRange<Double> = -15...15
    public static let frequencyGridlines: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000]
    public static let gainGridlines: [Double] = stride(from: -15.0, through: 15.0, by: 3.0).map { $0 }

    private static let decades = log(frequencyRange.upperBound / frequencyRange.lowerBound)

    public init(width: Double, height: Double) {
        self.width = width.isFinite ? max(width, 0) : 0
        self.height = height.isFinite ? max(height, 0) : 0
    }

    public static func frequencyLabel(_ hertz: Double) -> String {
        hertz >= 1000 ? "\(Int((hertz / 1000).rounded()))k" : "\(Int(hertz.rounded()))"
    }

    /// 0...1 on the log scale; input clamped to 20...20000, NaN counts as 20.
    public static func fraction(forFrequency hertz: Double) -> Double {
        guard !hertz.isNaN else { return 0 }
        let clamped = min(max(hertz, frequencyRange.lowerBound), frequencyRange.upperBound)
        return log(clamped / frequencyRange.lowerBound) / decades
    }

    public static func frequency(forFraction fraction: Double) -> Double {
        guard !fraction.isNaN else { return frequencyRange.lowerBound }
        let clamped = min(max(fraction, 0), 1)
        if clamped >= 1 { return frequencyRange.upperBound }
        return frequencyRange.lowerBound * exp(clamped * decades)
    }

    private var isDegenerate: Bool { width <= 0 || height <= 0 }

    public func x(forFrequency hertz: Double) -> Double {
        guard !isDegenerate else { return 0 }
        return width * Self.fraction(forFrequency: hertz)
    }

    public func frequency(forX x: Double) -> Double {
        guard !isDegenerate else { return 0 }
        return Self.frequency(forFraction: x / width)
    }

    public func y(forGain gain: Double) -> Double {
        guard !isDegenerate, !gain.isNaN else { return 0 }
        let clamped = min(max(gain, Self.decibelRange.lowerBound), Self.decibelRange.upperBound)
        return height * (Self.decibelRange.upperBound - clamped) / (Self.decibelRange.upperBound - Self.decibelRange.lowerBound)
    }

    public func gain(forY y: Double) -> Double {
        guard !isDegenerate, !y.isNaN else { return 0 }
        let clamped = min(max(y, 0), height)
        let span = Self.decibelRange.upperBound - Self.decibelRange.lowerBound
        return Self.decibelRange.upperBound - clamped / height * span
    }

    public func handlePosition(for band: EQBand) -> GraphPoint {
        GraphPoint(x: x(forFrequency: band.frequency), y: y(forGain: band.gain))
    }

    /// The enabled band whose handle is nearest to `point` within `radius`; on equal distance the
    /// highest index wins (it is drawn last, on top). Disabled bands are never returned.
    public func hitTest(_ point: GraphPoint, in curve: EQCurve, radius: Double) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, band) in curve.clamped().bands.enumerated() where band.enabled {
            let handle = handlePosition(for: band)
            let distance = hypot(handle.x - point.x, handle.y - point.y)
            guard distance <= radius else { continue }
            if best == nil || distance <= best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// The frequency and gain a drag to `point` means, clamped to the device limits (the axis is
    /// wider than the device range on purpose).
    public func dragged(to point: GraphPoint) -> (frequency: Double, gain: Double) {
        let frequency = min(max(frequency(forX: point.x), Double(JA11Limits.frequencyRange.lowerBound)),
                            Double(JA11Limits.frequencyRange.upperBound))
        let gain = min(max(gain(forY: point.y), JA11Limits.gainRange.lowerBound), JA11Limits.gainRange.upperBound)
        return (frequency, gain)
    }

    private func sampleFrequencies(_ points: Int) -> [(x: Double, frequency: Double)] {
        guard !isDegenerate, points >= 2 else { return [] }
        return (0..<points).map { i in
            let x = width * Double(i) / Double(points - 1)
            return (x, frequency(forX: x))
        }
    }

    /// The response of the enabled bands (with or without pre-gain) as plot points, evenly spaced
    /// in screen space and clipped to the +-15 dB axis.
    public func responsePoints(for curve: EQCurve, includePreGain: Bool, points: Int) -> [GraphPoint] {
        let clamped = curve.clamped()
        return sampleFrequencies(points).map { sample in
            let dB = includePreGain ? clamped.response(at: sample.frequency) : clamped.bandResponse(at: sample.frequency)
            return GraphPoint(x: sample.x, y: y(forGain: dB))
        }
    }

    /// Below the device's 0.1 dB resolution: the long tail of a boost is positive everywhere in
    /// theory but not worth marking.
    private static let clippingThreshold = 0.05

    /// X ranges where the response including pre-gain is above 0 dB (by more than half a tenth,
    /// so the tails of a boost do not count), ascending.
    public func clippingRanges(for curve: EQCurve, points: Int) -> [ClosedRange<Double>] {
        let clamped = curve.clamped()
        var ranges: [ClosedRange<Double>] = []
        var start: Double?
        var last = 0.0
        for sample in sampleFrequencies(points) {
            if clamped.response(at: sample.frequency) > Self.clippingThreshold {
                if start == nil { start = sample.x }
                last = sample.x
            } else if let begin = start {
                ranges.append(begin...last)
                start = nil
            }
        }
        if let begin = start { ranges.append(begin...last) }
        return ranges
    }
}
