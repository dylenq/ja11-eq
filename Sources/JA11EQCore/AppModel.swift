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
        case .readFailed(let error):
            readFailure = error.description
        case .disconnected:
            readFailure = nil
            setConnection(.notConnected)
        case .openFailed(let error):
            if case .accessDenied = error {
                setConnection(.accessRefused(error.description))
            } else {
                setConnection(.notConnected)
            }
        }
    }

    private func setConnection(_ status: ConnectionStatus) {
        guard status != connection else { return }
        connection = status
        statusLog.append(status)
        if statusLog.count > 50 { statusLog.removeFirst(statusLog.count - 50) }
    }
}
