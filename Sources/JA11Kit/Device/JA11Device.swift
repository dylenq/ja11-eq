import Foundation

/// Why a read from, or a write to, the JA11 did not produce a result.
public enum JA11Error: Error, Equatable, Sendable, CustomStringConvertible {
    /// No JA11 showed up within the discovery timeout.
    case notFound
    /// A read was asked for while no JA11 is connected.
    case notConnected
    /// A read was asked for while another one is still waiting for its reply, or a write operation
    /// while another one is under way. Nothing was sent.
    case busy
    /// The device did not answer this request in time.
    case noReply(JA11Command)
    /// The dongle was unplugged while a read was waiting.
    case disconnected
    /// A reply arrived for the right command but does not make sense.
    case unexpectedReply(String)
    /// The transport reported an error.
    case transport(HIDTransportError)
    /// A write sequence was ended before its save. The text says what was and was not sent.
    case writeInterrupted(String)
    /// The save was sent but no state could be read back afterwards, so nothing is confirmed.
    case noReadBack(String)

    public var description: String {
        switch self {
        case .notFound:
            "No JA11 found (looked for USB VID 0x2972, PID 0x0102). Plug the dongle in and run again."
        case .notConnected:
            "The JA11 is not connected."
        case .busy:
            "Another operation on the JA11 is still in progress."
        case .noReply(let command):
            "The JA11 did not answer the \(command.displayName) request."
        case .disconnected:
            "The JA11 was disconnected during the read."
        case .unexpectedReply(let text):
            "Unexpected reply from the JA11: \(text)"
        case .transport(let error):
            error.description
        case .writeInterrupted(let text):
            "The write was interrupted: \(text)"
        case .noReadBack(let text):
            "No read-back from the JA11: \(text)"
        }
    }
}

/// A change of the link seen after a save was sent.
public struct LinkEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case disconnected
        case connected
    }

    public let kind: Kind
    /// Time between the save frame and this change.
    public let secondsAfterSave: Double

    public init(kind: Kind, secondsAfterSave: Double) {
        self.kind = kind
        self.secondsAfterSave = secondsAfterSave
    }
}

/// The outcome of an apply: what was sent, what the device reported afterwards, and how they differ.
public struct ApplyReport: Sendable, Equatable {
    /// The state that was sent, clamped and at wire resolution.
    public let sent: EQState
    /// The state read from the device after the save.
    public let readBack: EQState
    /// One line per value that reads back differently; empty when everything matches.
    public let differences: [String]
    /// Disconnects and connects seen between the save and the end of the apply.
    public let linkEvents: [LinkEvent]

    public init(sent: EQState, readBack: EQState, differences: [String], linkEvents: [LinkEvent]) {
        self.sent = sent
        self.readBack = readBack
        self.differences = differences
        self.linkEvents = linkEvents
    }

    /// True only when the state read back from the device equals what was sent.
    public var isConfirmed: Bool {
        differences.isEmpty
    }
}

/// Which way a traced frame travelled.
public enum FrameDirection: Sendable {
    case sent
    case received
}

/// One step in the life of the link, as `JA11Device.watch()` reports it.
public enum LinkUpdate: Sendable, Equatable {
    /// A JA11 was connected. A read of its state follows.
    case connected
    /// The state read after the latest connect.
    case state(EQState)
    /// The read after the latest connect failed.
    case readFailed(JA11Error)
    /// The JA11 was unplugged.
    case disconnected
    /// A JA11 was found but could not be opened.
    case openFailed(HIDTransportError)
}

/// Reads the JA11's EQ state over a `ReportTransport`, and writes a curve to its USER1 slot.
///
/// Reads build read requests only. The write operations are internal: `JA11Writer` is the public
/// way to write, and it takes a backup first. They take every frame from a `FiioFrame` builder,
/// save to USER1 and to no other slot, run one at a time, and `apply(_:)` reports success only for
/// a state read back from the device after the save.
public actor JA11Device {
    /// The request that is waiting for its reply.
    private struct PendingRequest {
        let id: UInt64
        let command: JA11Command
        let accepts: @Sendable (FiioReplyFrame) -> Bool
        var continuation: CheckedContinuation<FiioReplyFrame?, any Error>?
    }

    private let transport: any ReportTransport
    private let replyTimeout: Duration
    private let discoveryTimeout: Duration
    /// Pause after each write frame.
    private let framePause: Duration
    /// Wait between the save and the first attempt to read back.
    private let saveSettle: Duration
    /// How long after the save a read-back may still arrive; the device may drop off USB meanwhile.
    private let reconnectTimeout: Duration
    /// Wait before the next attempt when the device is not usable yet after a save.
    private let readBackRetryWait: Duration
    private let trace: (@Sendable (FrameDirection, [UInt8]) -> Void)?

    private var started = false
    private var connected = false
    private var lastOpenError: HIDTransportError?
    private var connectionWaiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var nextID: UInt64 = 0

    /// True from the start of a request until its last attempt has ended, so reads never interleave.
    private var requestInFlight = false
    /// True for the whole duration of a write operation, so two of them never interleave.
    private var writeInProgress = false
    private var pending: PendingRequest?
    private var eventTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?

    /// Counts connects, so a read can tell that the dongle it began with is the one it ended with.
    private var connectionEpoch: UInt64 = 0
    /// Link changes since the save of the apply under way; nil while no apply is past its save.
    private var linkLog: (savedAt: ContinuousClock.Instant, events: [LinkEvent])?
    /// Where `watch()` receives link changes; nil while nobody is watching.
    private var watcher: (id: UInt64, continuation: AsyncStream<ConnectionEvent>.Continuation)?

    /// The request form the dongle answered; nil until a request was answered.
    public private(set) var frameForm: FrameForm?

    public init(
        transport: any ReportTransport,
        replyTimeout: Duration = .seconds(1),
        discoveryTimeout: Duration = .seconds(2),
        framePause: Duration = .milliseconds(100),
        saveSettle: Duration = .milliseconds(1500),
        reconnectTimeout: Duration = .seconds(10),
        readBackRetryWait: Duration = .milliseconds(200),
        trace: (@Sendable (FrameDirection, [UInt8]) -> Void)? = nil
    ) {
        self.transport = transport
        self.replyTimeout = replyTimeout
        self.discoveryTimeout = discoveryTimeout
        self.framePause = framePause
        self.saveSettle = saveSettle
        self.reconnectTimeout = reconnectTimeout
        self.readBackRetryWait = readBackRetryWait
        self.trace = trace
    }

    /// Starts the transport and begins following its events and reports. Later calls do nothing.
    public func start() {
        guard !started else { return }
        started = true
        transport.start()

        let events = transport.events
        let reports = transport.reports
        eventTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event: event)
            }
        }
        reportTask = Task { [weak self] in
            for await report in reports {
                await self?.handle(report: report)
            }
        }
    }

    /// Returns once a JA11 is connected.
    ///
    /// Throws `.transport` when the transport could not open the device, and `.notFound` when no
    /// JA11 showed up within the discovery timeout.
    public func waitForConnection() async throws {
        if connected { return }
        if let lastOpenError { throw JA11Error.transport(lastOpenError) }

        let id = makeID()
        let timeout = Task { [weak self, discoveryTimeout] in
            try? await Task.sleep(for: discoveryTimeout)
            guard !Task.isCancelled else { return }
            await self?.discoveryTimedOut(id)
        }
        defer { timeout.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connectionWaiters[id] = continuation
        }
    }

    /// The active preset slot as the device reports it.
    public func readSlot() async throws -> UInt8 {
        let reply = try await request(.presetSlot)
        guard let slot = reply.slotID() else { throw undecodable(.presetSlot, reply) }
        return slot
    }

    /// The number of filters in use as the device reports it.
    public func readFilterCount() async throws -> Int {
        let reply = try await request(.filterCount)
        guard let count = reply.filterCount() else { throw undecodable(.filterCount, reply) }
        return count
    }

    /// The pre-gain in dB as the device reports it.
    public func readPreGain() async throws -> Double {
        let reply = try await request(.preGain)
        guard let preGain = reply.preGain() else { throw undecodable(.preGain, reply) }
        return preGain
    }

    /// The filter at `index` as the device reports it.
    ///
    /// A filter reply that describes another index is not taken as the answer. `index` has to be
    /// one of the device's filter positions; asking for any other is a programming error, and
    /// nothing is sent.
    public func readFilter(index: Int) async throws -> Band {
        precondition(
            (0..<JA11Limits.maxBands).contains(index),
            "filter index \(index) is outside 0..<\(JA11Limits.maxBands)"
        )
        let reply = try await request(.filter, data: [UInt8(index)]) { reply in
            // A reply too short to decode is let through, so it is reported instead of timing out.
            guard let band = reply.band() else { return true }
            return band.index == index
        }
        guard let band = reply.band() else { throw undecodable(.filter, reply) }
        return band
    }

    /// The whole EQ state: slot, filter count, pre-gain, then every filter in index order.
    ///
    /// Each request is answered before the next one is sent. Any error ends the read: the result
    /// is either everything the device reported or nothing.
    ///
    /// A dongle that was unplugged and plugged back in while the read was under way ends it with
    /// `.disconnected`, so values from two connections are never combined into one state.
    public func readState() async throws -> EQState {
        let epoch = connectionEpoch
        let slotID = try await readSlot()

        let count = try await readFilterCount()
        guard count <= JA11Limits.maxBands else {
            throw JA11Error.unexpectedReply("filter count \(count) exceeds the device limit of \(JA11Limits.maxBands)")
        }

        let preGain = try await readPreGain()

        var bands: [Band] = []
        for index in 0..<count {
            bands.append(try await readFilter(index: index))
        }
        guard epoch == connectionEpoch else { throw JA11Error.disconnected }
        return EQState(slotID: slotID, preGain: preGain, bands: bands)
    }

    // MARK: - Writing

    /// Writes `curve` to USER1 and reads the device back.
    ///
    /// The curve is clamped first. USER1 is made the active slot, and seen to be, before any value
    /// is sent, so a filter write can never land in a factory preset's working copy. Then, in this
    /// order: pre-gain, filter count 5, filters 0 to 4, save to USER1, select USER1 — and a read of
    /// the whole state. The report is confirmed only when that read equals what was sent.
    ///
    /// Before the save nothing is forgiven: a send that fails, a link that is down or a dongle that
    /// was replugged ends the apply with `.writeInterrupted`, without a save, and no frame is sent
    /// again. After the save the device may drop off USB; until the reconnect timeout has passed
    /// the apply waits for it, selects USER1 and reads. `.noReadBack` when no read completed in
    /// that time. `.busy` when another write operation is under way; nothing is sent then.
    func apply(_ curve: EQCurve) async throws -> ApplyReport {
        try beginWrite()
        defer { writeInProgress = false }
        guard connected else { throw JA11Error.notConnected }

        let sent = curve.clamped().deviceState()
        let epoch = connectionEpoch

        try await makeUser1Active(epoch: epoch)

        try await sendValue(FiioFrame.setPreGain(sent.preGain), named: "pre-gain", epoch: epoch)
        try await sendValue(FiioFrame.setFilterCount(JA11Limits.maxBands), named: "filter count", epoch: epoch)
        for band in sent.bands {
            try await sendValue(FiioFrame.setFilter(band), named: "filter \(band.index)", epoch: epoch)
        }

        // A replugged dongle has lost the values sent before the replug; a save now would store a mix.
        guard connected, connectionEpoch == epoch else {
            throw JA11Error.writeInterrupted(
                "the link to the JA11 dropped before the save frame was due; the save was not sent, so nothing was saved."
            )
        }
        let clock = ContinuousClock()
        let savedAt = clock.now
        linkLog = (savedAt, [])
        defer { linkLog = nil }
        do {
            try transmit(FiioFrame.saveToUser1())
        } catch {
            throw JA11Error.writeInterrupted("the save frame could not be handed to the JA11 (\(error)); the save was not sent.")
        }
        try await Task.sleep(for: framePause)
        try await Task.sleep(for: saveSettle)

        // The device may be away for a while after a save. Until the deadline, each round waits
        // for the link, selects USER1 and reads everything. The select frame is the only write
        // frame that may go out more than once; the values and the save are never sent again.
        let deadline = savedAt + reconnectTimeout
        var lastFailure = "the JA11 did not come back"
        while clock.now < deadline {
            guard connected else {
                try await Task.sleep(for: min(Self.linkPoll, deadline - clock.now))
                continue
            }
            do {
                try await sendWrite(FiioFrame.selectSlot(.user1))
                let readBack = try await readState()
                return ApplyReport(
                    sent: sent,
                    readBack: readBack,
                    differences: readBack.differences(from: sent),
                    linkEvents: linkLog?.events ?? []
                )
            } catch let error as JA11Error {
                guard Self.meansNotUsableYet(error) else { throw error }
                lastFailure = error.description
            }
            let remaining = deadline - clock.now
            if remaining > .zero {
                try await Task.sleep(for: min(readBackRetryWait, remaining))
            }
        }
        throw JA11Error.noReadBack(
            "the save was sent, but no state could be read within \(reconnectTimeout) after it. Last attempt: \(lastFailure)"
        )
    }

    /// Makes `slot` the active preset and returns the slot the device reports afterwards.
    ///
    /// One select frame, a pause, one read. Nothing is compared here; the caller does that.
    /// `.busy` when another write operation is under way; nothing is sent then.
    func selectSlot(_ slot: PresetSlot) async throws -> UInt8 {
        try beginWrite()
        defer { writeInProgress = false }
        try await sendWrite(FiioFrame.selectSlot(slot))
        return try await readSlot()
    }

    /// Reads USER1's contents and notes the slot that was active (CONTEXT D-13).
    ///
    /// With USER1 active this sends no write frame. With another slot active it selects USER1,
    /// sees that the device switched, reads, and selects the slot that was active again, so taking
    /// a backup leaves the device as it was found.
    ///
    /// Throws `.unexpectedReply` when the active slot is not one this library can name, when the
    /// device does not switch, and when the state is not five filters of known type: a state that
    /// cannot be written back exactly is not a usable backup.
    func captureUser1() async throws -> DeviceBackup {
        try beginWrite()
        defer { writeInProgress = false }

        let original = try await readSlot()
        var originalSlot: PresetSlot?
        if original != JA11SlotID.user1 {
            guard let slot = PresetSlot(rawValue: original) else {
                throw JA11Error.unexpectedReply(
                    "the active slot is \(original), which is not a known preset; USER1 was not read and nothing was sent."
                )
            }
            originalSlot = slot
            try await sendWrite(FiioFrame.selectSlot(.user1))
            let now = try await readSlot()
            guard now == JA11SlotID.user1 else {
                throw JA11Error.unexpectedReply("the JA11 did not switch to USER1 (it reports slot \(now)); USER1 was not read.")
            }
        }

        let state = try await readState()
        guard state.slotID == JA11SlotID.user1 else {
            throw JA11Error.unexpectedReply("USER1 was not the active slot while it was read (slot \(state.slotID)).")
        }
        guard let curve = EQCurve(state: state) else {
            let types = state.bands.map { $0.type?.displayName ?? "type-\($0.typeID)" }.joined(separator: ", ")
            throw JA11Error.unexpectedReply(
                "USER1 holds \(state.bands.count) filters (\(types)); a backup needs \(JA11Limits.maxBands) filters of known type."
            )
        }

        if let originalSlot {
            try await sendWrite(FiioFrame.selectSlot(originalSlot))
            let now = try await readSlot()
            guard now == original else {
                throw JA11Error.unexpectedReply(
                    "the JA11 did not switch back to \(originalSlot.displayName) (it reports slot \(now))."
                )
            }
        }

        // Whole seconds, which is what the backup file holds.
        let savedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return DeviceBackup(savedAt: savedAt, activeSlot: original, curve: curve)
    }

    /// How often the link is looked at while an apply waits for the dongle to come back.
    private static let linkPoll: Duration = .milliseconds(10)

    /// Errors that, after a save, mean the device is not usable yet and another round may follow.
    private static func meansNotUsableYet(_ error: JA11Error) -> Bool {
        switch error {
        case .disconnected, .notConnected, .noReply, .busy:
            true
        case .transport(.notConnected), .transport(.sendFailed):
            true
        default:
            false
        }
    }

    /// Marks the start of a write operation, or refuses when one is under way.
    private func beginWrite() throws {
        guard !writeInProgress else { throw JA11Error.busy }
        writeInProgress = true
    }

    /// Sees to it that USER1 is the active slot before any value is sent.
    ///
    /// The select frame goes out at most once. Any error on the way, and a slot other than USER1
    /// afterwards, ends the apply with `.writeInterrupted`.
    private func makeUser1Active(epoch: UInt64) async throws {
        do {
            if try await readSlot() == JA11SlotID.user1 { return }
            try await sendWrite(FiioFrame.selectSlot(.user1))
            guard try await readSlot() == JA11SlotID.user1, connectionEpoch == epoch else {
                throw JA11Error.writeInterrupted("the JA11 did not switch to USER1; nothing was written and nothing was saved.")
            }
        } catch let error as JA11Error {
            if case .writeInterrupted = error { throw error }
            throw JA11Error.writeInterrupted(
                "USER1 could not be confirmed as the active slot (\(error.description)); no value was written and nothing was saved."
            )
        }
    }

    /// Sends one frame of the part of an apply that comes before the save, then pauses.
    ///
    /// Throws `.writeInterrupted` when the link is down, when the dongle is not the one the apply
    /// began with, or when the send fails. The frame is never sent a second time.
    private func sendValue(_ frame: [UInt8], named name: String, epoch: UInt64) async throws {
        guard connected, connectionEpoch == epoch else {
            throw JA11Error.writeInterrupted(
                "the link to the JA11 dropped before the \(name) frame was due; it was not sent, and nothing was saved."
            )
        }
        do {
            try transmit(frame)
        } catch {
            throw JA11Error.writeInterrupted("sending the \(name) frame failed (\(error)); nothing was saved.")
        }
        try await Task.sleep(for: framePause)
    }

    /// Hands one write frame to the transport, then pauses. Write frames are not answered.
    private func sendWrite(_ frame: [UInt8]) async throws {
        guard connected else { throw JA11Error.notConnected }
        try transmit(frame)
        try await Task.sleep(for: framePause)
    }

    /// Hands one write frame to the transport.
    private func transmit(_ frame: [UInt8]) throws {
        trace?(.sent, frame)
        do {
            try transport.send(frame)
        } catch let error as HIDTransportError {
            throw JA11Error.transport(error)
        }
    }

    // MARK: - Watching

    /// Follows the link: every connect, the state read after it, every disconnect.
    ///
    /// The stream starts the transport itself. It first reports the link as it is — for a JA11
    /// that is already connected, `.connected` and the outcome of a read — and then every change
    /// in the order it happened. Each connect is followed by a new `readState()`; a state read
    /// during an earlier connection is never reported again. A failed read is reported and the
    /// stream goes on. One watcher at a time: a later call ends the stream of the earlier one.
    public nonisolated func watch() -> AsyncStream<LinkUpdate> {
        let (updates, continuation) = AsyncStream.makeStream(of: LinkUpdate.self)
        let task = Task { await self.runWatch(yieldingTo: continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return updates
    }

    private func runWatch(yieldingTo updates: AsyncStream<LinkUpdate>.Continuation) async {
        let (links, linkContinuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        let id = makeID()
        watcher?.continuation.finish()
        watcher = (id, linkContinuation)

        // The link as it is now. Nothing can slip in between this and the registration above,
        // because the actor handles no event until this method first suspends.
        if connected {
            linkContinuation.yield(.connected)
        } else if let lastOpenError {
            linkContinuation.yield(.openFailed(lastOpenError))
        }
        start()

        // One update at a time, so the reads started here never overlap. While a read waits, the
        // actor keeps handling events, so an unplug ends that read at once.
        for await link in links {
            switch link {
            case .connected:
                updates.yield(.connected)
                do {
                    updates.yield(.state(try await readState()))
                } catch JA11Error.disconnected, JA11Error.notConnected {
                    // The `.disconnected` update that follows covers it.
                } catch let error as JA11Error {
                    updates.yield(.readFailed(error))
                } catch {
                    updates.yield(.readFailed(.unexpectedReply(String(describing: error))))
                }
            case .disconnected:
                updates.yield(.disconnected)
            case .openFailed(let error):
                updates.yield(.openFailed(error))
            }
        }

        if watcher?.id == id { watcher = nil }
        updates.finish()
    }

    // MARK: - Requests

    /// Sends one read request and returns the reply that answers it.
    ///
    /// Until the dongle has answered once, the request goes out zero-padded first and, if that goes
    /// unanswered, once more unpadded. The form that was answered is used for every later request.
    /// Apart from that one fallback there are no retries.
    private func request(
        _ command: JA11Command,
        data: [UInt8] = [],
        accepting accepts: @escaping @Sendable (FiioReplyFrame) -> Bool = { _ in true }
    ) async throws -> FiioReplyFrame {
        guard connected else { throw JA11Error.notConnected }
        guard !requestInFlight else { throw JA11Error.busy }
        requestInFlight = true
        defer { requestInFlight = false }

        let forms: [FrameForm] = if let frameForm { [frameForm] } else { [.padded, .unpadded] }
        for (attempt, form) in forms.enumerated() {
            // An unplug between the two attempts ends the read; nothing more is sent.
            if attempt > 0, !connected { throw JA11Error.disconnected }
            if let reply = try await exchange(command, data: data, form: form, accepting: accepts) {
                frameForm = form
                return reply
            }
        }
        throw JA11Error.noReply(command)
    }

    /// One frame out, then a wait for its reply. Returns nil when the reply timeout passes first.
    private func exchange(
        _ command: JA11Command,
        data: [UInt8],
        form: FrameForm,
        accepting accepts: @escaping @Sendable (FiioReplyFrame) -> Bool
    ) async throws -> FiioReplyFrame? {
        let frame = FiioFrame.getRequest(command, data: data, form: form)
        trace?(.sent, frame)

        // The expectation is recorded before the frame is handed over, because a transport may
        // deliver the answer before `send` returns.
        let id = makeID()
        pending = PendingRequest(id: id, command: command, accepts: accepts, continuation: nil)
        do {
            try transport.send(frame)
        } catch let error as HIDTransportError {
            pending = nil
            throw JA11Error.transport(error)
        } catch {
            pending = nil
            throw error
        }

        let timeout = Task { [weak self, replyTimeout] in
            try? await Task.sleep(for: replyTimeout)
            guard !Task.isCancelled else { return }
            await self?.replyTimedOut(id)
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FiioReplyFrame?, any Error>) in
            guard pending?.id == id else {
                // The expectation is already gone, so there is no reply to wait for.
                continuation.resume(returning: nil)
                return
            }
            pending?.continuation = continuation
        }
    }

    private func undecodable(_ command: JA11Command, _ reply: FiioReplyFrame) -> JA11Error {
        .unexpectedReply("cannot decode the \(command.displayName) reply (\(FiioFrame.hex(reply.bytes)))")
    }

    private func makeID() -> UInt64 {
        nextID += 1
        return nextID
    }

    // MARK: - Transport input

    private func handle(event: ConnectionEvent) {
        defer { watcher?.continuation.yield(event) }
        recordForApply(event)
        switch event {
        case .connected:
            connected = true
            connectionEpoch += 1
            lastOpenError = nil
            resumeConnectionWaiters(with: .success(()))
        case .disconnected:
            connected = false
            if let waiting = pending {
                pending = nil
                waiting.continuation?.resume(throwing: JA11Error.disconnected)
            }
        case .openFailed(let error):
            lastOpenError = error
            resumeConnectionWaiters(with: .failure(JA11Error.transport(error)))
        }
    }

    /// Notes a connect or disconnect for the apply that is past its save, if there is one.
    private func recordForApply(_ event: ConnectionEvent) {
        guard let log = linkLog else { return }
        let kind: LinkEvent.Kind
        switch event {
        case .connected: kind = .connected
        case .disconnected: kind = .disconnected
        case .openFailed: return
        }
        let elapsed = ContinuousClock.now - log.savedAt
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        linkLog?.events.append(LinkEvent(kind: kind, secondsAfterSave: seconds))
    }

    private func handle(report: [UInt8]) {
        trace?(.received, report)
        guard let waiting = pending,
              let reply = FiioFrame.replyFrame(from: report),
              reply.command == waiting.command.rawValue,
              waiting.accepts(reply)
        else { return }
        pending = nil
        waiting.continuation?.resume(returning: reply)
    }

    private func replyTimedOut(_ id: UInt64) {
        guard let waiting = pending, waiting.id == id else { return }
        pending = nil
        waiting.continuation?.resume(returning: nil)
    }

    private func discoveryTimedOut(_ id: UInt64) {
        connectionWaiters.removeValue(forKey: id)?.resume(throwing: JA11Error.notFound)
    }

    private func resumeConnectionWaiters(with result: Result<Void, any Error>) {
        let waiters = connectionWaiters.values
        connectionWaiters = [:]
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}
