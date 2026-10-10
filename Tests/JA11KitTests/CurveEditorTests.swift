import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

private func sampleCurve(preGain: Double = 0.0) -> EQCurve {
    EQCurve(preGain: preGain, bands: [
        EQBand(type: .lowShelf, frequency: 100, gain: 0, q: 0.7),
        EQBand(type: .peak, frequency: 200, gain: 0, q: 1.0),
        EQBand(type: .peak, frequency: 1000, gain: 0, q: 1.0),
        EQBand(type: .peak, frequency: 4000, gain: 0, q: 1.0),
        EQBand(type: .highShelf, frequency: 10000, gain: 0, q: 0.7),
    ])
}

private func loaded(_ curve: EQCurve? = nil, editable: Bool = true) -> CurveEditor {
    var editor = CurveEditor.empty
    editor.load(curve ?? sampleCurve(), editable: editable)
    return editor
}

@Suite struct CurveEditorTests {
    @Test func emptyEditor() {
        let editor = CurveEditor.empty
        #expect(editor.curve.bands == Array(repeating: EQBand.neutral, count: 5))
        #expect(editor.curve.preGain == 0.0)
        #expect(!editor.isEditable)
        #expect(!editor.isDirty)
        var copy = editor
        copy.setGain(5, band: 0)
        copy.setPreGain(3)
        copy.setEnabled(true, band: 1)
        #expect(copy == editor)
    }

    @Test func loadStoresClampedCurveCleanAndEditable() {
        var curve = sampleCurve()
        curve.bands[0].gain = 3.04
        let editor = loaded(curve)
        #expect(editor.curve == curve.clamped())
        #expect(editor.baseline == editor.curve)
        #expect(!editor.isDirty)
        #expect(editor.isEditable)
    }

    @Test func loadPadsFourBandsToFive() {
        var curve = sampleCurve()
        curve.bands.removeLast()
        let editor = loaded(curve)
        #expect(editor.curve.bands.count == 5)
        #expect(editor.curve.bands[4] == .neutral)
    }

    @Test func autoOnLoad() {
        #expect(loaded(sampleCurve(preGain: 0.0)).autoPreGain)
        #expect(!loaded(sampleCurve(preGain: 1.0)).autoPreGain)
        var boosted = sampleCurve()
        boosted.bands[2].gain = 6
        boosted.preGain = boosted.autoPreGain()
        #expect(loaded(boosted).autoPreGain)
        boosted.preGain = -1
        #expect(!loaded(boosted).autoPreGain)
    }

    @Test(arguments: [
        (-12.1, -12.0), (-12.0, -12.0), (-11.9, -11.9), (12.0, 12.0), (12.1, 12.0),
        (0.04, 0.0), (0.05, 0.1), (-0.05, -0.1), (.nan, 0.0), (.infinity, 12.0), (-.infinity, -12.0),
    ])
    func gainClamps(input: Double, expected: Double) {
        var editor = loaded()
        editor.setGain(input, band: 1)
        #expect(editor.curve.bands[1].gain == expected)
        var moved = loaded()
        moved.moveBand(1, frequency: 1000, gain: input)
        #expect(moved.curve.bands[1].gain == expected)
    }

    @Test(arguments: [
        (0.09, 0.1), (0.1, 0.1), (0.11, 0.11), (10.0, 10.0), (10.01, 10.0), (1.006, 1.01), (1.004, 1.0),
        (.nan, 0.1), (.infinity, 10.0), (-.infinity, 0.1),
    ])
    func qClamps(input: Double, expected: Double) {
        var editor = loaded()
        editor.setQ(input, band: 2)
        #expect(editor.curve.bands[2].q == expected)
    }

    @Test(arguments: [
        (19.0, 20.0), (20.0, 20.0), (20000.0, 20000.0), (20001.0, 20000.0),
        (.nan, 20.0), (.infinity, 20000.0), (-.infinity, 20.0), (999.6, 1000.0),
    ])
    func frequencyClamps(input: Double, expected: Double) {
        var editor = loaded()
        editor.setFrequency(input, band: 3)
        #expect(editor.curve.bands[3].frequency == expected)
        var moved = loaded()
        moved.moveBand(3, frequency: input, gain: 0)
        #expect(moved.curve.bands[3].frequency == expected)
    }

    @Test(arguments: [(-12.1, -12.0), (-12.0, -12.0), (12.0, 12.0), (12.1, 12.0), (.nan, 0.0), (-3.0, -3.0)])
    func preGainClamps(input: Double, expected: Double) {
        var editor = loaded()
        editor.setAutoPreGain(false)
        editor.setPreGain(input)
        #expect(editor.curve.preGain == expected)
    }

    @Test(arguments: [-1, 5, 99])
    func indexGuard(index: Int) {
        let editor = loaded()
        var copy = editor
        copy.setEnabled(false, band: index)
        copy.setType(.highShelf, band: index)
        copy.setFrequency(500, band: index)
        copy.setGain(5, band: index)
        copy.setQ(3, band: index)
        copy.moveBand(index, frequency: 500, gain: 5)
        copy.scaleQ(band: index, by: 2)
        #expect(copy == editor)
    }

    @Test func fieldsAreIndependent() {
        var editor = loaded()
        let before = editor.curve.bands[2]
        editor.setType(.lowShelf, band: 2)
        #expect(editor.curve.bands[2].type == .lowShelf)
        #expect(editor.curve.bands[2].frequency == before.frequency)
        #expect(editor.curve.bands[2].gain == before.gain)
        editor.setGain(4, band: 2)
        editor.setEnabled(false, band: 2)
        #expect(editor.curve.bands[2].gain == 4.0)
        #expect(!editor.curve.bands[2].enabled)
        #expect(editor.curve.bands[2].q == before.q)
    }

    @Test func readOnlyIgnoresEverything() {
        let editor = loaded(editable: false)
        var copy = editor
        copy.setEnabled(false, band: 0)
        copy.setType(.highShelf, band: 0)
        copy.setFrequency(500, band: 0)
        copy.setGain(5, band: 0)
        copy.setQ(3, band: 0)
        copy.moveBand(0, frequency: 500, gain: 5)
        copy.scaleQ(band: 0, by: 2)
        copy.setPreGain(-5)
        copy.setAutoPreGain(!editor.autoPreGain)
        #expect(copy == editor)
    }

    @Test func dirtyTracking() {
        var editor = loaded()
        #expect(!editor.isDirty)
        editor.setGain(3, band: 0)
        #expect(editor.isDirty)
        editor.setGain(0, band: 0)
        #expect(!editor.isDirty)
        editor.setEnabled(false, band: 1)
        #expect(editor.isDirty)
        editor.setEnabled(true, band: 1)
        #expect(!editor.isDirty)
        editor.setFrequency(777, band: 4)
        editor.markApplied()
        #expect(!editor.isDirty)
        #expect(editor.baseline == editor.curve)
        editor.setFrequency(900, band: 4)
        #expect(editor.isDirty)
        editor.revert()
        #expect(!editor.isDirty)
        #expect(editor.curve.bands[4].frequency == 777)
    }

    @Test func bandsAreNeverSorted() {
        var editor = loaded()
        editor.setFrequency(500, band: 0)
        #expect(editor.curve.bands[0].frequency == 500)
        #expect(editor.curve.bands[1].frequency == 200)
        #expect(editor.curve.bands[0].type == .lowShelf)
        editor.moveBand(0, frequency: 9000, gain: 0)
        #expect(editor.curve.bands.map(\.frequency) == [9000, 200, 1000, 4000, 10000])
    }

    @Test func coincidentBandsBothKept() {
        var editor = loaded()
        editor.setGain(3, band: 0)
        editor.setGain(-2, band: 1)
        editor.setFrequency(1000, band: 0)
        editor.setFrequency(1000, band: 1)
        #expect(editor.curve.bands.count == 5)
        #expect(editor.curve.bands[0].gain == 3.0 && editor.curve.bands[1].gain == -2.0)
        #expect(editor.curve.bands[0].type == .lowShelf && editor.curve.bands[1].type == .peak)
        #expect(editor.curve.bands[0].q == 0.7 && editor.curve.bands[1].q == 1.0)
    }

    @Test func autoCouplingFollowsEveryEdit() {
        var editor = loaded()
        #expect(editor.autoPreGain)
        editor.setGain(6, band: 0)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        #expect(editor.curve.preGain < 0)
        editor.setEnabled(false, band: 0)
        #expect(editor.curve.preGain == 0.0)
        editor.setEnabled(true, band: 0)
        editor.setType(.peak, band: 0)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        editor.setQ(5, band: 0)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        editor.setFrequency(3000, band: 0)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        editor.moveBand(0, frequency: 50, gain: 9)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        editor.scaleQ(band: 0, by: 2)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        let auto = editor.curve.preGain
        editor.setPreGain(3)
        #expect(editor.curve.preGain == auto)
        editor.setAutoPreGain(false)
        #expect(editor.curve.preGain == auto)
        editor.setPreGain(-3)
        #expect(editor.curve.preGain == -3.0)
        editor.setGain(1, band: 3)
        #expect(editor.curve.preGain == -3.0)
        editor.setAutoPreGain(true)
        #expect(editor.curve.preGain == editor.curve.autoPreGain())
        #expect(editor.isDirty)
    }

    @Test func autoEmptyAndOrder() {
        var editor = loaded()
        for i in 0..<5 { editor.setGain(6, band: i) }
        for i in 0..<5 { editor.setEnabled(false, band: i) }
        #expect(editor.curve.preGain == 0.0)
        var zero = loaded()
        zero.setGain(0, band: 2)
        #expect(zero.curve.preGain == 0.0)

        var curve = sampleCurve()
        curve.bands[0].gain = 7
        curve.bands[3].gain = 4
        var swapped = curve
        swapped.bands.swapAt(0, 3)
        #expect(curve.autoPreGain() == swapped.autoPreGain())
        let a = loaded(curve), b = loaded(swapped)
        var a2 = a, b2 = b
        a2.setAutoPreGain(true)
        b2.setAutoPreGain(true)
        #expect(a2.curve.preGain == b2.curve.preGain)
    }

    @Test func moveBandAndScaleQ() {
        var editor = loaded()
        let before = editor.curve.bands[2]
        editor.moveBand(2, frequency: 5000, gain: 3.04)
        #expect(editor.curve.bands[2].frequency == 5000)
        #expect(editor.curve.bands[2].gain == 3.0)
        #expect(editor.curve.bands[2].q == before.q)
        #expect(editor.curve.bands[2].type == before.type)
        editor.scaleQ(band: 2, by: 2)
        #expect(editor.curve.bands[2].q == 2.0)
        editor.scaleQ(band: 2, by: 100)
        #expect(editor.curve.bands[2].q == 10.0)
        editor.scaleQ(band: 2, by: 0.0001)
        #expect(editor.curve.bands[2].q == 0.1)
    }
}
