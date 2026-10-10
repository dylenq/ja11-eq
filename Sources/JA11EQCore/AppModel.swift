import Foundation
import Observation
import JA11Kit

/// The app's state and the only holder of a `JA11Device`. It follows `JA11Device.watch()` and the
/// output sample rate. Nothing here writes to the dongle: loading sends read requests only.
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

    @ObservationIgnored private var reconnectSeen = true

    @ObservationIgnored private let device: JA11Device
    @ObservationIgnored private let sampleRates: any OutputSampleRateSource
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var rateTask: Task<Void, Never>?

    public init(device: JA11Device, sampleRates: any OutputSampleRateSource = CoreAudioSampleRate()) {
        self.device = device
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
    public var editorEnabled: Bool { connection == .connected && editor.isEditable }

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
            setConnection(.connected)
        case .state(let state):
            deviceState = state
            readFailure = nil
            stateLoadCount += 1
            loadEditor(from: state)
        case .readFailed(let error):
            readFailure = error.description
        case .disconnected:
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
