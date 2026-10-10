/// Why a read from the JA11 did not produce a value.
public enum JA11Error: Error, Equatable, Sendable, CustomStringConvertible {
    /// No JA11 showed up within the discovery timeout.
    case notFound
    /// A read was asked for while no JA11 is connected.
    case notConnected
    /// A read was asked for while another one is still waiting for its reply.
    case busy
    /// The device did not answer this request in time.
    case noReply(JA11Command)
    /// The dongle was unplugged while a read was waiting.
    case disconnected
    /// A reply arrived for the right command but does not make sense.
    case unexpectedReply(String)
    /// The transport reported an error.
    case transport(HIDTransportError)

    public var description: String {
        switch self {
        case .notFound:
            "No JA11 found (looked for USB VID 0x2972, PID 0x0102). Plug the dongle in and run again."
        case .notConnected:
            "The JA11 is not connected."
        case .busy:
            "Another read is still in progress."
        case .noReply(let command):
            "The JA11 did not answer the \(command.displayName) request."
        case .disconnected:
            "The JA11 was disconnected during the read."
        case .unexpectedReply(let text):
            "Unexpected reply from the JA11: \(text)"
        case .transport(let error):
            error.description
        }
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

/// Reads the JA11's EQ state over a `ReportTransport`.
///
/// The actor offers read operations only: every frame it builds is a read request, and nothing
/// here changes what is stored on the device.
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
    private let trace: (@Sendable (FrameDirection, [UInt8]) -> Void)?

    private var started = false
    private var connected = false
    private var lastOpenError: HIDTransportError?
    private var connectionWaiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var nextID: UInt64 = 0

    /// True from the start of a request until its last attempt has ended, so reads never interleave.
    private var requestInFlight = false
    private var pending: PendingRequest?
    private var eventTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?

    /// Counts connects, so a read can tell that the dongle it began with is the one it ended with.
    private var connectionEpoch: UInt64 = 0
    /// Where `watch()` receives link changes; nil while nobody is watching.
    private var watcher: (id: UInt64, continuation: AsyncStream<ConnectionEvent>.Continuation)?

    /// The request form the dongle answered; nil until a request was answered.
    public private(set) var frameForm: FrameForm?

    public init(
        transport: any ReportTransport,
        replyTimeout: Duration = .seconds(1),
        discoveryTimeout: Duration = .seconds(2),
        trace: (@Sendable (FrameDirection, [UInt8]) -> Void)? = nil
    ) {
        self.transport = transport
        self.replyTimeout = replyTimeout
        self.discoveryTimeout = discoveryTimeout
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
