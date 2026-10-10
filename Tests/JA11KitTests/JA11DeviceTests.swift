import Foundation
import Testing
@testable import JA11Kit

/// A transport that exists only in memory: it records what it is asked to send and delivers the
/// reports a test tells it to. It never calls IOKit, so nothing here can reach a real dongle.
final class FakeTransport: ReportTransport, @unchecked Sendable {
    let events: AsyncStream<ConnectionEvent>
    let reports: AsyncStream<[UInt8]>

    private let eventsContinuation: AsyncStream<ConnectionEvent>.Continuation
    private let reportsContinuation: AsyncStream<[UInt8]>.Continuation
    private let lock = NSLock()
    private var sentPayloads: [[UInt8]] = []
    private var currentResponder: ([UInt8]) -> [[UInt8]] = { _ in [] }

    init() {
        (events, eventsContinuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        (reports, reportsContinuation) = AsyncStream.makeStream(of: [UInt8].self)
    }

    /// Every payload given to `send`, in order.
    var sent: [[UInt8]] {
        lock.withLock { sentPayloads }
    }

    /// The reports to deliver for a sent payload. The default delivers none.
    var responder: ([UInt8]) -> [[UInt8]] {
        get { lock.withLock { currentResponder } }
        set { lock.withLock { currentResponder = newValue } }
    }

    func start() {}

    func send(_ payload: [UInt8]) throws {
        let respond = lock.withLock { () -> ([UInt8]) -> [[UInt8]] in
            sentPayloads.append(payload)
            return currentResponder
        }
        for report in respond(payload) {
            reportsContinuation.yield(report)
        }
    }

    func emit(_ event: ConnectionEvent) {
        eventsContinuation.yield(event)
    }

    func emit(report: [UInt8]) {
        reportsContinuation.yield(report)
    }
}

/// Collects values from concurrently running code.
final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    var values: [Value] {
        lock.withLock { stored }
    }

    func append(_ value: Value) {
        lock.withLock { stored.append(value) }
    }
}

/// Device behaviour tests. Every one runs on a `FakeTransport`, so they pass with the dongle
/// unplugged and cannot send anything.
@Suite struct JA11DeviceTests {
    // MARK: - Reply vectors

    static let slot3: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x16, 0x01, 0x03, 0x00, 0xEE]
    static let preGainMinus6: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x02, 0xFF, 0xC4, 0x00, 0xEE]
    static let preGainPlus3: [UInt8] = [0xBB, 0x0B, 0x00, 0x00, 0x17, 0x02, 0x00, 0x1E, 0x00, 0xEE]
    /// Filter 0: low shelf, 100 Hz, +6.0 dB, Q 0.70.
    static let filter0: [UInt8] = [
        0xBB, 0x0B, 0x00, 0x00, 0x15, 0x08, 0x00, 0x00, 0x3C, 0x00, 0x64, 0x00, 0x46, 0x01, 0x00, 0xEE,
    ]
    /// Filter 1: peak, 1000 Hz, -6.0 dB, Q 1.41.
    static let filter1: [UInt8] = [
        0xBB, 0x0B, 0x00, 0x00, 0x15, 0x08, 0x01, 0xFF, 0xC4, 0x03, 0xE8, 0x00, 0x8D, 0x00, 0x00, 0xEE,
    ]

    static func count(_ value: UInt8) -> [UInt8] {
        [0xBB, 0x0B, 0x00, 0x00, 0x18, 0x01, value, 0x00, 0xEE]
    }

    /// A filter reply with another index byte and otherwise the same values.
    static func filter(_ frame: [UInt8], index: UInt8) -> [UInt8] {
        var copy = frame
        copy[6] = index
        return copy
    }

    /// A frame as a 20-byte report, optionally with the report-ID byte in front.
    static func report(_ frame: [UInt8], leadingID: Bool = false) -> [UInt8] {
        let padded = frame + [UInt8](repeating: 0x00, count: max(0, JA11.payloadLength - frame.count))
        return leadingID ? [JA11.reportID] + padded : padded
    }

    /// The state the default replies describe.
    static let stateA = EQState(
        slotID: 3,
        preGain: -6.0,
        bands: [
            Band(index: 0, typeID: 1, frequency: 100, gain: 6.0, q: 0.70),
            Band(index: 1, typeID: 0, frequency: 1000, gain: -6.0, q: 1.41),
        ]
    )

    /// A responder that answers a full read: slot 3, the given count, pre-gain and filters.
    ///
    /// A filter request is answered with the entry of `filters` at the requested index, when there
    /// is one. `onlyUnpadded` makes it ignore 20-byte requests.
    static func replies(
        count: UInt8 = 2,
        preGain: [UInt8]? = preGainMinus6,
        filters: [[UInt8]] = [filter0, filter1],
        leadingID: Bool = false,
        onlyUnpadded: Bool = false
    ) -> ([UInt8]) -> [[UInt8]] {
        { payload in
            if onlyUnpadded, payload.count == JA11.payloadLength { return [] }
            guard payload.count > 6 else { return [] }
            let frame: [UInt8]?
            switch payload[4] {
            case 0x16: frame = slot3
            case 0x18: frame = Self.count(count)
            case 0x17: frame = preGain
            case 0x15: frame = filters.indices.contains(Int(payload[6])) ? filters[Int(payload[6])] : nil
            default: frame = nil
            }
            return frame.map { [report($0, leadingID: leadingID)] } ?? []
        }
    }

    // MARK: - Helpers

    /// A device on a fake transport, started, and connected unless told otherwise.
    static func makeDevice(
        connected: Bool = true,
        replyTimeout: Duration = .milliseconds(100),
        trace: (@Sendable (FrameDirection, [UInt8]) -> Void)? = nil
    ) async throws -> (JA11Device, FakeTransport) {
        let fake = FakeTransport()
        let device = JA11Device(
            transport: fake,
            replyTimeout: replyTimeout,
            discoveryTimeout: .milliseconds(100),
            trace: trace
        )
        await device.start()
        if connected {
            fake.emit(.connected)
            try await device.waitForConnection()
        }
        return (device, fake)
    }

    /// Waits until `condition` holds, for at most two seconds. Returns whether it came to hold.
    static func waitUntil(_ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }

    /// The error a read ended with, or nil when it returned a value.
    static func failure<T: Sendable>(of read: () async throws -> T) async -> JA11Error? {
        do {
            _ = try await read()
            return nil
        } catch let error as JA11Error {
            return error
        } catch {
            return .unexpectedReply("not a JA11Error: \(error)")
        }
    }

    // MARK: - Full read (D-03, D-04, D-06, D-11)

    @Test func fullReadReturnsTheStateAndAsksInTheFixedOrder() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies()

        let state = try await device.readState()

        #expect(state == Self.stateA)
        let sent = fake.sent
        #expect(sent.map { $0[4] } == [0x16, 0x18, 0x17, 0x15, 0x15])
        #expect(sent.suffix(2).map { $0[6] } == [0, 1])
        #expect(sent.allSatisfy(FiioFrame.isGetRequest))
        #expect(sent.allSatisfy { $0.count == 20 })
        #expect(await device.frameForm == .padded)
    }

    @Test func repliesWithALeadingReportIDByteGiveTheSameState() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(leadingID: true)

        #expect(try await device.readState() == Self.stateA)
    }

    // MARK: - Frame form (D-03)

    @Test func fallsBackToTheUnpaddedFormOnceAndKeepsIt() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(onlyUnpadded: true)

        #expect(try await device.readState() == Self.stateA)

        let sent = fake.sent
        #expect(sent.count == 6)
        #expect(sent.first == FiioFrame.getRequest(.presetSlot, form: .padded))
        #expect(sent.dropFirst().first == FiioFrame.getRequest(.presetSlot, form: .unpadded))
        #expect(sent.dropFirst().allSatisfy { $0.count == 8 || $0.count == 9 })
        #expect(sent.dropFirst().map { $0[4] } == [0x16, 0x18, 0x17, 0x15, 0x15])
        #expect(sent.allSatisfy(FiioFrame.isGetRequest))
        #expect(await device.frameForm == .unpadded)

        #expect(try await device.readState() == Self.stateA)
        let second = Array(fake.sent.dropFirst(6))
        #expect(second.count == 5)
        #expect(second.allSatisfy { $0.count == 8 || $0.count == 9 })
    }

    @Test func aDeviceThatAnswersNeitherFormIsReportedAfterTwoSends() async throws {
        let (device, fake) = try await Self.makeDevice()

        #expect(await Self.failure { try await device.readSlot() } == .noReply(.presetSlot))

        #expect(fake.sent == [
            FiioFrame.getRequest(.presetSlot, form: .padded),
            FiioFrame.getRequest(.presetSlot, form: .unpadded),
        ])
        #expect(await device.frameForm == nil)
    }

    // MARK: - Filter count (D-11)

    @Test func aCountOfZeroGivesNoFiltersAndSendsNoFilterRequest() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(count: 0)

        let state = try await device.readState()

        #expect(state.bands.isEmpty)
        #expect(state.reportLines().contains("filters: 0"))
        #expect(fake.sent.count == 3)
        #expect(!fake.sent.contains { $0[4] == 0x15 })
    }

    @Test func aCountAboveFiveIsAnErrorNamingTheValueAndSendsNoFilterRequest() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(count: 6)

        let error = await Self.failure { try await device.readState() }

        guard case .unexpectedReply(let text) = error else {
            Issue.record("expected unexpectedReply, got \(String(describing: error))")
            return
        }
        #expect(text.contains("6"))
        #expect(!fake.sent.contains { $0[4] == 0x15 })
    }

    @Test func filtersComeBackInAscendingIndexOrder() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(count: 5, filters: (0..<5).map { Self.filter(Self.filter1, index: $0) })

        let state = try await device.readState()

        #expect(state.bands.map(\.index) == [0, 1, 2, 3, 4])
        #expect(fake.sent.suffix(5).map { $0[6] } == [0, 1, 2, 3, 4])
    }

    @Test func twoIdenticalFiltersStayTwoEntriesUnderTheirOwnIndexes() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(filters: [Self.filter0, Self.filter(Self.filter0, index: 1)])

        let bands = try await device.readState().bands

        #expect(bands.count == 2)
        #expect(bands.map(\.index) == [0, 1])
        var second = bands[1]
        second.index = 0
        #expect(second == bands[0])
    }

    // MARK: - Missing and mismatched replies (D-11)

    @Test func aMissingPreGainReplyIsADidNotAnswerErrorWithoutAFallbackFrame() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies(preGain: nil)

        let started = ContinuousClock.now
        let error = await Self.failure { try await device.readState() }
        let elapsed = ContinuousClock.now - started

        #expect(error == .noReply(.preGain))
        #expect(error?.description.contains("did not answer") == true)
        #expect(elapsed < .seconds(2))
        #expect(fake.sent.count == 3)
        #expect(fake.sent.allSatisfy { $0.count == 20 })
    }

    @Test func aStaleReplyForAnotherCommandIsNotTakenAsTheAnswer() async throws {
        let (device, fake) = try await Self.makeDevice()
        let normal = Self.replies()
        fake.responder = { payload in
            payload[4] == 0x18 ? [Self.report(Self.slot3), Self.report(Self.count(2))] : normal(payload)
        }

        #expect(try await device.readSlot() == 3)
        #expect(try await device.readFilterCount() == 2)
    }

    @Test func aFilterReplyWithAnotherIndexIsNotTakenAsTheAnswer() async throws {
        let (device, fake) = try await Self.makeDevice()
        // Whatever index is asked for, the reply describes filter 0.
        fake.responder = Self.replies(filters: [Self.filter0, Self.filter0])

        #expect(await Self.failure { try await device.readState() } == .noReply(.filter))
        #expect(fake.sent.last?[6] == 1)
    }

    @Test func reportsThatAreNotRepliesAreIgnored() async throws {
        let (device, fake) = try await Self.makeDevice()
        var headerless = Self.report(Self.slot3)
        headerless[0] = 0x00
        let noise = [[UInt8](repeating: 0x00, count: 20), headerless]
        fake.responder = { payload in
            payload[4] == 0x16 ? noise + [Self.report(Self.slot3)] : []
        }

        #expect(try await device.readSlot() == 3)
    }

    // MARK: - Interruption and parallel use (LINK-02)

    @Test func anUnplugEndsAWaitingReadAtOnce() async throws {
        let (device, fake) = try await Self.makeDevice(replyTimeout: .seconds(5))
        let read = Task { await Self.failure { try await device.readSlot() } }
        #expect(await Self.waitUntil { fake.sent.count == 1 })

        let unplugged = ContinuousClock.now
        fake.emit(.disconnected)
        let error = await read.value

        #expect(error == .disconnected)
        #expect(ContinuousClock.now - unplugged < .seconds(1))
        #expect(fake.sent.count == 1)
    }

    @Test func aSecondReadWhileOneIsWaitingIsRefusedAsBusy() async throws {
        let (device, fake) = try await Self.makeDevice(replyTimeout: .seconds(5))
        let first = Task { await Self.failure { try await device.readSlot() } }
        #expect(await Self.waitUntil { fake.sent.count == 1 })

        #expect(await Self.failure { try await device.readSlot() } == .busy)
        #expect(fake.sent.count == 1)

        fake.emit(.disconnected)
        _ = await first.value
    }

    @Test func aReadBeforeAnyConnectionSendsNothing() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false)

        #expect(await Self.failure { try await device.readSlot() } == .notConnected)
        #expect(fake.sent.isEmpty)
    }

    @Test func aReplugInTheMiddleOfAReadEndsThatRead() async throws {
        let (device, fake) = try await Self.makeDevice()
        let normal = Self.replies()
        // The dongle goes away and comes back between the slot reply and the count reply.
        fake.responder = { payload in
            if payload[4] == 0x18 {
                fake.emit(.disconnected)
                fake.emit(.connected)
            }
            return normal(payload)
        }

        #expect(await Self.failure { try await device.readState() } == .disconnected)
    }

    // MARK: - Watching the link (D-09, D-14)

    /// Starts watching and collects every update.
    static func collect(_ device: JA11Device) -> Recorder<LinkUpdate> {
        let log = Recorder<LinkUpdate>()
        let updates = device.watch()
        Task {
            for await update in updates {
                log.append(update)
            }
        }
        return log
    }

    static var stateB: EQState {
        var state = stateA
        state.preGain = 3.0
        return state
    }

    @Test func watchReadsOnConnectAndReadsAgainAfterAReplug() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false)
        fake.responder = Self.replies()
        let log = Self.collect(device)

        fake.emit(.connected)
        #expect(await Self.waitUntil { log.values.count == 2 })
        #expect(log.values == [.connected, .state(Self.stateA)])

        fake.emit(.disconnected)
        #expect(await Self.waitUntil { log.values.count == 3 })
        #expect(log.values.last == .disconnected)

        fake.responder = Self.replies(preGain: Self.preGainPlus3)
        fake.emit(.connected)
        #expect(await Self.waitUntil { log.values.count == 5 })
        #expect(log.values == [
            .connected, .state(Self.stateA), .disconnected, .connected, .state(Self.stateB),
        ])
    }

    @Test func watchFollowsThreeConnectAndDisconnectCyclesInOrder() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false)
        fake.responder = Self.replies()
        let log = Self.collect(device)

        for cycle in 1...3 {
            fake.emit(.connected)
            #expect(await Self.waitUntil { log.values.count == cycle * 3 - 1 })
            fake.emit(.disconnected)
            #expect(await Self.waitUntil { log.values.count == cycle * 3 })
        }

        let cycleUpdates: [LinkUpdate] = [.connected, .state(Self.stateA), .disconnected]
        #expect(log.values == cycleUpdates + cycleUpdates + cycleUpdates)
    }

    @Test func watchReportsAFailedReadAndStillFollowsTheNextConnect() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false)
        let log = Self.collect(device)

        fake.emit(.connected)
        #expect(await Self.waitUntil { log.values.count == 2 })
        #expect(log.values == [.connected, .readFailed(.noReply(.presetSlot))])

        fake.emit(.disconnected)
        #expect(await Self.waitUntil { log.values.count == 3 })
        fake.responder = Self.replies()
        fake.emit(.connected)
        #expect(await Self.waitUntil { log.values.count == 5 })
        #expect(Array(log.values.dropFirst(2)) == [.disconnected, .connected, .state(Self.stateA)])
    }

    @Test func watchPassesOnAFailedOpen() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false)
        let refusal = HIDTransportError.accessDenied(code: Int32(bitPattern: 0xE00002E2))
        let log = Self.collect(device)

        fake.emit(.openFailed(refusal))

        #expect(await Self.waitUntil { log.values.count == 1 })
        #expect(log.values == [.openFailed(refusal)])
    }

    @Test func watchStartsWithAReadWhenTheDeviceIsAlreadyConnected() async throws {
        let (device, fake) = try await Self.makeDevice()
        fake.responder = Self.replies()

        let log = Self.collect(device)

        #expect(await Self.waitUntil { log.values.count == 2 })
        #expect(log.values == [.connected, .state(Self.stateA)])
    }

    @Test func watchStartsTheTransportItself() async throws {
        let fake = FakeTransport()
        fake.responder = Self.replies()
        let device = JA11Device(transport: fake, replyTimeout: .milliseconds(100))
        let log = Self.collect(device)

        fake.emit(.connected)

        #expect(await Self.waitUntil { log.values.count == 2 })
        #expect(log.values == [.connected, .state(Self.stateA)])
    }

    @Test func anUnplugDuringTheWatchersReadShowsAsDisconnectedOnly() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false, replyTimeout: .seconds(5))
        let log = Self.collect(device)

        fake.emit(.connected)
        #expect(await Self.waitUntil { fake.sent.count == 1 })
        let unplugged = ContinuousClock.now
        fake.emit(.disconnected)

        #expect(await Self.waitUntil { log.values.count == 2 })
        #expect(ContinuousClock.now - unplugged < .seconds(1))
        #expect(log.values == [.connected, .disconnected])
    }

    // MARK: - Discovery (D-10, D-13)

    @Test func noDongleWithinTheDiscoveryTimeoutIsNotFound() async throws {
        let (device, _) = try await Self.makeDevice(connected: false)

        #expect(await Self.failure { try await device.waitForConnection() } == .notFound)
    }

    @Test func aRefusedOpenIsReportedAsTheTransportError() async throws {
        let (device, fake) = try await Self.makeDevice(connected: false)
        let refusal = HIDTransportError.accessDenied(code: Int32(bitPattern: 0xE00002E2))

        fake.emit(.openFailed(refusal))

        #expect(await Self.failure { try await device.waitForConnection() } == .transport(refusal))
    }
}
