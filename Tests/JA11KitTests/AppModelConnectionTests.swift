import Foundation
import Testing
@testable import JA11Kit
@testable import JA11EQCore

/// A sample-rate source that yields nothing but nil. Later plans reuse it.
struct NilSampleRates: OutputSampleRateSource {
    func rates() -> AsyncStream<Double?> {
        AsyncStream { continuation in
            continuation.yield(nil)
        }
    }
}

/// Polls on the main actor every 2 ms until the condition holds; records an Issue on timeout.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ message: String = "condition",
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            Issue.record("timed out waiting for \(message)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// Builds a started AppModel on a FakeDongle. Later plans reuse it.
@MainActor
enum AppModelFixture {
    static func make(
        dongle: FakeDongle,
        connected: Bool = true,
        sampleRates: any OutputSampleRateSource = NilSampleRates()
    ) async throws -> AppModel {
        let device = try await ApplyTests.makeDevice(on: dongle, connected: false)
        let model = AppModel(device: device, sampleRates: sampleRates)
        model.start()
        if connected { dongle.transport.emit(.connected) }
        return model
    }
}

@MainActor
@Suite struct AppModelConnectionTests {
    @Test func connectedDongleShowsStateAndCustomPreset() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("state loaded") { model.deviceState != nil }

        #expect(model.connection == .connected)
        #expect(model.deviceState == dongle.state)
        #expect(model.activePresetTitle == "Custom")
        #expect(model.stateLoadCount == 1)
        #expect(model.statusLog.last == .connected)
        model.stop()
    }

    @Test func slotTitles() async throws {
        let expected: [(UInt8, String)] = [(0, "Vocal"), (1, "Classic"), (2, "Bass"), (4, "Off")]
        for (slot, title) in expected {
            let dongle = FakeDongle(slot: slot)
            let model = try await AppModelFixture.make(dongle: dongle)
            await waitUntil("state for slot \(slot)") { model.deviceState != nil }
            #expect(model.activePresetTitle == title)
            model.stop()
        }
    }

    @Test func unknownSlotAndNoStateTitles() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle, connected: false)
        #expect(model.activePresetTitle == "\u{2014}")
        model.handle(.state(EQState(slotID: 9, preGain: 0, bands: [])))
        #expect(model.activePresetTitle == "Unknown (9)")
        model.stop()
    }

    @Test func loadingSendsReadRequestsOnly() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("state loaded") { model.deviceState != nil }

        #expect(dongle.writeFrames.isEmpty)
        let sent = dongle.transport.sent
        #expect(!sent.isEmpty)
        #expect(sent.allSatisfy { $0.starts(with: [0xBB, 0x0B]) })
        model.stop()
    }

    @Test func unplugAndReplug() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("first load") { model.stateLoadCount == 1 }

        dongle.transport.emit(.disconnected)
        await waitUntil("not connected") { model.connection == .notConnected }
        #expect(model.connection.detail == "Plug in the JA11")

        dongle.transport.emit(.connected)
        await waitUntil("reload") { model.stateLoadCount == 2 }
        #expect(model.connection == .connected)
        #expect(model.deviceState == dongle.state)
        model.stop()
    }

    @Test func noDeviceStartsAtOnceAndSendsNothing() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle, connected: false)
        model.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.connection == .notConnected)
        #expect(model.deviceState == nil)
        #expect(model.activePresetTitle == "\u{2014}")
        #expect(dongle.transport.sent.isEmpty)
        model.stop()
    }

    @Test func accessDeniedShowsInputMonitoringText() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle, connected: false)
        dongle.transport.emit(.openFailed(.accessDenied(code: -536870174)))
        await waitUntil("access refused") {
            if case .accessRefused = model.connection { true } else { false }
        }
        guard case .accessRefused(let text) = model.connection else {
            Issue.record("not refused")
            return
        }
        #expect(text.contains("Input Monitoring"))
        #expect(model.connection.title == "Access refused")
        model.stop()
    }

    @Test func otherOpenFailureIsNotConnected() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle, connected: false)
        model.handle(.openFailed(.accessDenied(code: 1)))
        model.handle(.openFailed(.openFailed(code: 1)))
        #expect(model.connection == .notConnected)
        model.stop()
    }

    @Test func failedReadKeepsConnectedAndStreamGoesOn() async throws {
        let dongle = FakeDongle()
        dongle.transport.responder = { _ in [] }
        let model = try await AppModelFixture.make(dongle: dongle)
        await waitUntil("read failure") { model.readFailure != nil }

        #expect(model.connection == .connected)
        #expect(model.deviceState == nil)
        #expect(model.readFailure?.contains("did not answer") == true)

        dongle.transport.emit(.disconnected)
        await waitUntil("not connected") { model.connection == .notConnected }

        model.handle(.state(dongle.state))
        #expect(model.readFailure == nil)
        model.stop()
    }

    @Test func startTwiceRunsOneWatchLoop() async throws {
        let dongle = FakeDongle()
        let model = try await AppModelFixture.make(dongle: dongle)
        model.start()
        await waitUntil("state loaded") { model.stateLoadCount >= 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.stateLoadCount == 1)
        model.stop()
    }

    @Test func everyLinkUpdateMapsToOneOfThreeStates() {
        let dongle = FakeDongle()
        let device = JA11Device(transport: dongle.transport)
        let model = AppModel(device: device, sampleRates: NilSampleRates())
        let updates: [LinkUpdate] = [
            .connected, .state(dongle.state), .readFailed(.busy), .disconnected,
            .openFailed(.accessDenied(code: 1)), .openFailed(.notConnected),
        ]
        for update in updates {
            model.handle(update)
            switch model.connection {
            case .notConnected, .connected, .accessRefused: break
            }
        }
        #expect(model.statusLog.count <= 50)
    }
}
