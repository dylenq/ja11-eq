import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

private let geo = GraphGeometry(width: 800, height: 300)

private func flat(preGain: Double = 0) -> EQCurve {
    EQCurve(preGain: preGain, bands: Array(repeating: EQBand(type: .peak, frequency: 1000, gain: 0, q: 1, enabled: true), count: 5))
}

private func curve(_ bands: [EQBand], preGain: Double = 0) -> EQCurve {
    var all = bands
    while all.count < 5 { all.append(.neutral) }
    return EQCurve(preGain: preGain, bands: all)
}

@Suite struct GraphGeometryTests {
    @Test func frequencyToX() {
        #expect(geo.x(forFrequency: 20) == 0)
        #expect(abs(geo.x(forFrequency: 20000) - 800) < 1e-9)
        #expect(abs(geo.x(forFrequency: 1000) - 800 * log(50) / log(1000)) < 1e-9)
        #expect(abs(geo.x(forFrequency: 200) - 800 / 3) < 1e-9)
        #expect(geo.x(forFrequency: 5) == 0)
        #expect(geo.x(forFrequency: 50000) == 800)
        #expect(geo.x(forFrequency: .nan) == 0)
    }

    @Test func xInvertsFrequency() {
        for i in 0..<25 {
            let f = 20 * pow(1000.0, Double(i) / 24)
            let back = geo.frequency(forX: geo.x(forFrequency: f))
            #expect(abs(back - f) / f < 1e-9)
        }
        #expect(geo.frequency(forX: -10) == 20)
        #expect(abs(geo.frequency(forX: 900) - 20000) < 1e-6)
    }

    @Test func gainToY() {
        #expect(geo.y(forGain: 15) == 0)
        #expect(geo.y(forGain: -15) == 300)
        #expect(geo.y(forGain: 0) == 150)
        #expect(abs(geo.y(forGain: 7.5) - 75) < 1e-9)
        #expect(geo.y(forGain: 40) == 0)
        #expect(geo.y(forGain: -40) == 300)
        for g in stride(from: -15.0, through: 15.0, by: 2.5) {
            #expect(abs(geo.gain(forY: geo.y(forGain: g)) - g) < 1e-9)
        }
        #expect(geo.gain(forY: -50) == 15)
        #expect(geo.gain(forY: 999) == -15)
    }

    @Test func octaveSymmetry() {
        let a = geo.x(forFrequency: 40) - geo.x(forFrequency: 20)
        let b = geo.x(forFrequency: 80) - geo.x(forFrequency: 40)
        #expect(abs(a - b) < 1e-9)
    }

    @Test func gridlines() {
        #expect(GraphGeometry.frequencyGridlines == [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000])
        #expect(GraphGeometry.frequencyGridlines.map { GraphGeometry.frequencyLabel($0) }
            == ["20", "50", "100", "200", "500", "1k", "2k", "5k", "10k", "20k"])
        #expect(GraphGeometry.gainGridlines.count == 11)
        #expect(GraphGeometry.gainGridlines.first == -15 && GraphGeometry.gainGridlines.last == 15)
        #expect(GraphGeometry.gainGridlines.contains(0))
    }

    @Test func fraction() {
        #expect(GraphGeometry.fraction(forFrequency: 20) == 0)
        #expect(abs(GraphGeometry.fraction(forFrequency: 20000) - 1) < 1e-12)
        #expect(GraphGeometry.frequency(forFraction: -1) == 20)
        #expect(abs(GraphGeometry.frequency(forFraction: 2) - 20000) < 1e-6)
        #expect(abs(GraphGeometry.frequency(forFraction: GraphGeometry.fraction(forFrequency: 440)) - 440) < 1e-9)
    }

    @Test func dragToValue() {
        let p = GraphPoint(x: geo.x(forFrequency: 1000), y: geo.y(forGain: 3))
        let d = geo.dragged(to: p)
        #expect(abs(d.frequency - 1000) < 0.5)
        #expect(abs(d.gain - 3.0) < 0.05)
        #expect(geo.dragged(to: GraphPoint(x: -50, y: 150)).frequency == 20)
        #expect(geo.dragged(to: GraphPoint(x: 5000, y: 150)).frequency == 20000)
        #expect(geo.dragged(to: GraphPoint(x: 100, y: -80)).gain == 12.0)
        #expect(geo.dragged(to: GraphPoint(x: 100, y: 900)).gain == -12.0)
        #expect(abs(geo.dragged(to: GraphPoint(x: 100, y: geo.y(forGain: 12))).gain - 12.0) < 1e-9)

        var editor = CurveEditor.empty
        editor.load(flat(), editable: true)
        let far = geo.dragged(to: GraphPoint(x: -999, y: -999))
        editor.moveBand(0, frequency: far.frequency, gain: far.gain)
        #expect(editor.curve.bands[0].frequency == 20 && editor.curve.bands[0].gain == 12.0)
    }

    @Test func handlePosition() {
        let band = EQBand(type: .peak, frequency: 1000, gain: 3, q: 1)
        let h = geo.handlePosition(for: band)
        #expect(h == GraphPoint(x: geo.x(forFrequency: 1000), y: geo.y(forGain: 3)))
    }

    @Test func hitTest() {
        var bands = [EQBand](repeating: .neutral, count: 5)
        bands[0] = EQBand(type: .peak, frequency: 200, gain: 3, q: 1)
        bands[1] = EQBand(type: .peak, frequency: 1000, gain: -3, q: 1)
        bands[2] = EQBand(type: .peak, frequency: 1000, gain: -3, q: 1)
        bands[3] = EQBand(type: .peak, frequency: 5000, gain: 6, q: 1, enabled: false)
        let c = curve(bands)
        let h0 = geo.handlePosition(for: c.bands[0])
        #expect(geo.hitTest(GraphPoint(x: h0.x + 5, y: h0.y), in: c, radius: 12) == 0)
        #expect(geo.hitTest(GraphPoint(x: h0.x + 13, y: h0.y), in: c, radius: 12) == nil)
        let h1 = geo.handlePosition(for: c.bands[1])
        #expect(geo.hitTest(h1, in: c, radius: 12) == 2)
        let h3 = geo.handlePosition(for: c.bands[3])
        #expect(geo.hitTest(h3, in: c, radius: 12) == nil)

        var near = bands
        near[2] = EQBand(type: .peak, frequency: 1000, gain: -2.8, q: 1)
        let c2 = curve(near)
        let p = GraphPoint(x: h1.x, y: h1.y - 2)
        #expect(geo.hitTest(p, in: c2, radius: 12) == 2)
        let p2 = GraphPoint(x: h1.x, y: h1.y + 1)
        #expect(geo.hitTest(p2, in: c2, radius: 12) == 1)

        let off = EQCurve(preGain: 0, bands: Array(repeating: .neutral, count: 5))
        #expect(geo.hitTest(GraphPoint(x: 400, y: 150), in: off, radius: 12) == nil)
    }

    @Test func responsePoints() {
        let pts = geo.responsePoints(for: flat(), includePreGain: false, points: 100)
        #expect(pts.count == 100)
        #expect(pts.first?.x == 0 && abs(pts.last!.x - 800) < 1e-9)
        #expect(zip(pts, pts.dropFirst()).allSatisfy { $0.x < $1.x })
        #expect(pts.allSatisfy { abs($0.y - geo.y(forGain: 0)) < 1e-9 })

        let peak = curve([EQBand(type: .peak, frequency: 1000, gain: 12, q: 1)])
        let pp = geo.responsePoints(for: peak, includePreGain: false, points: 800)
        let top = pp.min { $0.y < $1.y }!
        #expect(abs(top.y - geo.y(forGain: 12)) <= 1)
        #expect(abs(top.x - geo.x(forFrequency: 1000)) < 20)

        let stacked = curve(Array(repeating: EQBand(type: .peak, frequency: 1000, gain: 12, q: 1), count: 5))
        let sp = geo.responsePoints(for: stacked, includePreGain: false, points: 200)
        #expect(sp.min { $0.y < $1.y }!.y == 0)
        #expect(sp.allSatisfy { $0.y >= 0 && $0.y <= 300 })

        let base = geo.responsePoints(for: flat(preGain: -6), includePreGain: false, points: 10)
        let with = geo.responsePoints(for: flat(preGain: -6), includePreGain: true, points: 10)
        let delta = geo.y(forGain: -6) - geo.y(forGain: 0)
        for (a, b) in zip(base, with) { #expect(abs((b.y - a.y) - delta) < 1e-9) }
    }

    @Test func clipping() {
        #expect(geo.clippingRanges(for: flat(), points: 400).isEmpty)
        let peak = curve([EQBand(type: .peak, frequency: 1000, gain: 6, q: 1)])
        let r = geo.clippingRanges(for: peak, points: 800)
        #expect(r.count == 1)
        #expect(r[0].contains(geo.x(forFrequency: 1000)))

        var fixed = peak
        fixed.preGain = peak.autoPreGain()
        #expect(geo.clippingRanges(for: fixed, points: 800).isEmpty)
        var low = peak
        low.preGain = -12
        #expect(geo.clippingRanges(for: low, points: 800).isEmpty)

        let two = curve([
            EQBand(type: .peak, frequency: 200, gain: 6, q: 10),
            EQBand(type: .peak, frequency: 5000, gain: 6, q: 10),
        ])
        let rr = geo.clippingRanges(for: two, points: 800)
        #expect(rr.count == 2, "\(rr)")
        #expect(rr[0].upperBound < rr[1].lowerBound)
        #expect(rr.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= 800 })
    }

    @Test func degenerateSize() {
        for g in [GraphGeometry(width: 0, height: 300), GraphGeometry(width: 800, height: 0)] {
            #expect(g.x(forFrequency: 1000) == 0)
            #expect(g.frequency(forX: 10) == 0 || g.frequency(forX: 10) == 20)
            #expect(g.y(forGain: 3) == 0)
            #expect(g.gain(forY: 10) == 0 || g.gain(forY: 10).isFinite)
            #expect(g.responsePoints(for: flat(), includePreGain: true, points: 50).isEmpty)
            #expect(g.clippingRanges(for: flat(), points: 50).isEmpty)
            _ = g.dragged(to: GraphPoint(x: 1, y: 1))
            _ = g.hitTest(GraphPoint(x: 1, y: 1), in: flat(), radius: 12)
        }
    }
}
