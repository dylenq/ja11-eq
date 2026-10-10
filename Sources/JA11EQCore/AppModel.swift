import Foundation
import Observation
import JA11Kit

/// The app's state and the only holder of a `JA11Device`. It follows `JA11Device.watch()` and the
/// output sample rate. Every write goes through `JA11Writer` (apply, selectSlot, restore), which takes
/// the backup first; loading sends read requests only.
@MainActor
@Observable
public final class AppModel {
    public private(set) var connection: ConnectionStatus = .notConnected
    public private(set) var deviceState: EQState?
    public private(set) var readFailure: String?
    public private(set) var sampleRateText: String = missingValueText
    public private(set) var statusLog: [ConnectionStatus] = [.notConnected]
    public private(set) var stateLoadCount: Int = 0
    /// The curve being edited. Views change it through the `CurveEditor` operations, guarded by
    /// `editorEnabled`; the type itself ignores edits while it is read-only.
    public var editor: CurveEditor = .empty

    /// What the model is doing to the dongle right now; one operation at a time.
    public private(set) var operation: OperationState = .idle
    /// How the last operation ended.
    public private(set) var outcome: OperationOutcome?
    public private(set) var pendingPreset: PresetChoice?
    public private(set) var restoreConfirmationPending = false

    @ObservationIgnored private var reconnectSeen = true
    /// True from a `.connected` update until the read that follows it has ended.
    @ObservationIgnored private var readInFlight = false
    /// A `.disconnected` seen during an operation, not yet shown.
    @ObservationIgnored private var deferredDisconnect = false

    /// A refusal as busy at the start of an operation sent nothing, so it may be retried.
    static let busyRetries = 10
    static let busyRetryWait: Duration = .milliseconds(100)
    /// How long an operation waits for the watch loop's read of a connect.
    static let quietLinkTimeout: Duration = .seconds(5)
    static let quietLinkPoll: Duration = .milliseconds(20)

    @ObservationIgnored private let device: JA11Device
    @ObservationIgnored private let writer: JA11Writer
    @ObservationIgnored private let sampleRates: any OutputSampleRateSource
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var rateTask: Task<Void, Never>?

    public init(
        device: JA11Device,
        writer: JA11Writer? = nil,
        sampleRates: any OutputSampleRateSource = CoreAudioSampleRate()
    ) {
        self.device = device
        self.writer = writer ?? JA11Writer(device: device)
        self.sampleRates = sampleRates
    }

    public static func live() -> AppModel {
        AppModel(device: JA11Device(transport: HIDTransport()))
    }

    /// The title of the active preset: a known name, `Unknown (n)`, or an em dash without a state.
    public var activePresetTitle: String {
        guard let deviceState else { return missingValueText }
        if let choice = PresetChoice(slotID: deviceState.slotID) { return choice.title }
        return "Unknown (\(deviceState.slotID))"
    }

    /// True while the dongle is connected and the editor may change.
    public var editorEnabled: Bool { connection == .connected && editor.isEditable && operation == .idle }

    /// Apply is offered only for the editable USER1 slot with unsaved changes and nothing in flight.
    public var canApply: Bool {
        connection == .connected
            && deviceState?.slotID == JA11SlotID.user1
            && editor.isEditable
            && editor.isDirty
            && operation == .idle
    }

    public var canRevert: Bool { connection == .connected && editor.isDirty && operation == .idle }
    public var canSelectPreset: Bool { connection == .connected && operation == .idle }
    public var canRestore: Bool { connection == .connected && operation == .idle }

    /// The preset the DAC reported last, if it is one of the five.
    public var activePreset: PresetChoice? {
        deviceState.flatMap { PresetChoice(slotID: $0.slotID) }
    }

    /// A confirmation is hidden once the editor has changed again; everything else stays.
    public var visibleOutcome: OperationOutcome? {
        if case .confirmed = outcome, editor.isDirty { return nil }
        return outcome
    }

    /// A one-line note shown when a loaded slot cannot be edited.
    public var editorNote: String? {
        guard let deviceState, PresetChoice(slotID: deviceState.slotID)?.isEditable != true,
              editor != .empty
        else { return nil }
        return "Only Custom can be edited. Choose Custom in the preset picker."
    }

    /// Starts following the dongle and the sample rate. Returns at once; safe to call twice.
    public func start() {
        if watchTask == nil {
            let updates = device.watch()
            watchTask = Task { [weak self] in
                for await update in updates {
                    guard let self else { return }
                    self.handle(update)
                }
            }
        }
        if rateTask == nil {
            let rates = sampleRates.rates()
            rateTask = Task { [weak self] in
                for await rate in rates {
                    guard let self else { return }
                    self.sampleRateText = SampleRateFormat.text(rate)
                }
            }
        }
    }

    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        rateTask?.cancel()
        rateTask = nil
    }

    /// The only place link state changes.
    func handle(_ update: LinkUpdate) {
        switch update {
        case .connected:
            readInFlight = true
            deferredDisconnect = false
            setConnection(.connected)
        case .state(let state):
            readInFlight = false
            // What the watch loop read during an operation is not loaded; the operation shows its own.
            guard !operation.isBusy else { return }
            deviceState = state
            readFailure = nil
            stateLoadCount += 1
            loadEditor(from: state)
        case .readFailed(let error):
            readInFlight = false
            guard !operation.isBusy else { return }
            readFailure = error.description
        case .disconnected:
            readInFlight = false
            if operation.isBusy {
                // The dongle drops by itself after every save; shown only if it does not return.
                deferredDisconnect = true
                return
            }
            readFailure = nil
            reconnectSeen = true
            setConnection(.notConnected)
        case .openFailed(let error):
            if case .accessDenied = error {
                setConnection(.accessRefused(error.description))
            } else {
                setConnection(.notConnected)
            }
        }
    }

    // MARK: - Operations

    /// Sends the edited curve to USER1 through the writer and reports what the DAC read back.
    public func apply() async {
        guard canApply else { return }
        // Set before the first await: this is what makes a second press a no-op.
        begin(.applying)
        let curve = editor.curve
        await waitForQuietLink()
        do {
            let report = try await retryingBusy { try await writer.apply(curve) }
            deviceState = report.readBack
            if report.isConfirmed {
                editor.markApplied()
                outcome = .confirmed("Applied and confirmed")
            } else {
                outcome = .mismatch(report.differences)
            }
        } catch {
            outcome = .failed(Self.describe(error))
        }
        finishOperation()
    }

    func begin(_ state: OperationState) {
        operation = state
        outcome = nil
    }

    /// Ends the current operation and shows a Not connected that was held back, if the dongle never returned.
    func finishOperation() {
        operation = .idle
        if deferredDisconnect {
            deferredDisconnect = false
            readFailure = nil
            reconnectSeen = true
            setConnection(.notConnected)
        }
    }

    /// Waits (at most `quietLinkTimeout`) for the watch loop's read of a connect to end, so the
    /// operation does not collide with it.
    func waitForQuietLink() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.quietLinkTimeout)
        while readInFlight, clock.now < deadline {
            try? await Task.sleep(for: Self.quietLinkPoll)
        }
    }

    /// Retries only the exact busy refusal, which means nothing was sent.
    func retryingBusy<T>(_ work: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await work()
            } catch JA11Error.busy where attempt < Self.busyRetries {
                attempt += 1
                try? await Task.sleep(for: Self.busyRetryWait)
            }
        }
    }

    static func describe(_ error: any Error) -> String {
        if let text = error as? any CustomStringConvertible { return text.description }
        return error.localizedDescription
    }

    private func loadEditor(from state: EQState) {
        guard let curve = EQCurve(state: state) else {
            editor = .empty
            readFailure = Self.unshowableReason(state)
            return
        }
        // A dirty editor is only replaced after a genuine reconnect.
        guard !editor.isDirty || reconnectSeen else { return }
        editor.load(curve, editable: PresetChoice(slotID: state.slotID)?.isEditable == true)
        reconnectSeen = false
    }

    private static func unshowableReason(_ state: EQState) -> String {
        if state.bands.count != JA11Limits.maxBands {
            return "The JA11 reports \(state.bands.count) filters instead of \(JA11Limits.maxBands); the editor cannot show it."
        }
        if let band = state.bands.first(where: { $0.type == nil }) {
            return "Filter \(band.index + 1) has an unknown type (\(band.typeID)); the editor cannot show it."
        }
        return "The editor cannot show this state."
    }

    private func setConnection(_ status: ConnectionStatus) {
        guard status != connection else { return }
        connection = status
        statusLog.append(status)
        if statusLog.count > 50 { statusLog.removeFirst(statusLog.count - 50) }
    }
}
