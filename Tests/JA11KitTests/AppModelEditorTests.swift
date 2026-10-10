import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

@MainActor
@Suite struct AppModelEditorTests {
    @Test func user1ConnectLoadsEditableEditor() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("state loaded") { model.deviceState != nil }

        let expected = EQCurve(state: dongle.user1)!.clamped()
        #expect(model.editor.curve == expected)
        #expect(!model.editor.isDirty)
        #expect(model.editor.isEditable)
        #expect(model.editorEnabled)
        #expect(model.editorNote == nil)
        model.stop()
    }

    @Test(arguments: [UInt8(0), 1, 2, 4])
    func factorySlotIsReadOnly(slot: UInt8) async throws {
        let dongle = FakeDongle(slot: slot)
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("state loaded") { model.deviceState != nil }

        #expect(model.editor.curve.bands.map(\.frequency) == FakeDongle.factoryBands.map { Double($0.frequency) })
        #expect(model.editor.curve.preGain == -2.0)
        #expect(!model.editor.isEditable)
        #expect(!model.editorEnabled)
        #expect(model.editorNote == "Only Custom can be edited. Choose Custom in the preset picker.")
        let before = model.editor
        model.editor.setGain(5, band: 0)
        #expect(model.editor == before)
        model.stop()
    }

    @Test func disconnectDisablesAndReconnectReloads() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("first load") { model.stateLoadCount == 1 }
        let curve = model.editor.curve

        dongle.transport.emit(.disconnected)
        await waitUntil("not connected") { model.connection == .notConnected }
        #expect(model.editor.curve == curve)
        #expect(!model.editorEnabled)

        dongle.transport.emit(.connected)
        await waitUntil("reload") { model.stateLoadCount == 2 }
        #expect(model.editorEnabled)
        model.stop()
    }

    @Test(arguments: [0, 1])
    func unshowableStateLeavesEmptyEditor(which: Int) async throws {
        let dongle = which == 0
            ? FakeDongle(filterCount: 4)
            : FakeDongle(typeOverride: (index: 2, typeID: 7))
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("failure shown") { model.readFailure != nil }

        #expect(model.editor == CurveEditor.empty)
        #expect(model.readFailure?.isEmpty == false)
        #expect(!model.editorEnabled)
        model.stop()
    }

    @Test func dirtyEditorSurvivesPlainStateUpdate() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("loaded") { model.stateLoadCount == 1 }

        model.editor.setGain(4, band: 0)
        #expect(model.editor.isDirty)
        let edited = model.editor
        model.handle(.state(dongle.state))
        #expect(model.editor == edited)
        #expect(model.stateLoadCount == 2)
        model.stop()
    }

    @Test func genuineReconnectReloadsDirtyEditor() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("loaded") { model.stateLoadCount == 1 }
        model.editor.setGain(4, band: 0)
        #expect(model.editor.isDirty)

        model.handle(.disconnected)
        model.handle(.connected)
        model.handle(.state(dongle.state))
        #expect(!model.editor.isDirty)
        #expect(model.editor.curve == EQCurve(state: dongle.state)!.clamped())
        model.stop()
    }

    @Test func cleanEditorTakesEveryNewState() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("loaded") { model.stateLoadCount == 1 }

        var changed = dongle.state
        changed.bands[1].gain = 3.0
        model.handle(.state(changed))
        #expect(model.editor.curve.bands[1].gain == 3.0)
        #expect(!model.editor.isDirty)
        model.stop()
    }

    @Test func loadingAndReconnectWriteNothing() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("first load") { model.stateLoadCount == 1 }
        dongle.transport.emit(.disconnected)
        dongle.transport.emit(.connected)
        await waitUntil("reload") { model.stateLoadCount == 2 }
        #expect(dongle.writeFrames.isEmpty)
        model.stop()
    }
}
