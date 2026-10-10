import Foundation

/// What the model is doing to the dongle right now. Only one operation runs at a time.
public enum OperationState: Equatable, Sendable {
    case idle
    case applying
    case restoring
    case switchingPreset
    case reloading

    public var isBusy: Bool { self != .idle }

    /// The short text shown beside the progress indicator, or nil when idle.
    public var progressText: String? {
        switch self {
        case .idle: nil
        case .applying: "Applying... this takes about 4 seconds"
        case .restoring: "Restoring the original... this takes about 4 seconds"
        case .switchingPreset: "Switching preset..."
        case .reloading: "Reading the JA11..."
        }
    }
}

/// How the last operation ended, in words the user can act on.
public enum OperationOutcome: Equatable, Sendable {
    /// The read-back matched: "Applied and confirmed".
    case confirmed(String)
    /// The DAC read back different values; one line per difference.
    case mismatch([String])
    /// An error description or a sentence.
    case failed(String)
    /// Something that worked but needs no confirmation: "Switched to Bass".
    case info(String)

    /// True only for outcomes that may be shown as success.
    public var isSuccess: Bool {
        switch self {
        case .confirmed, .info: true
        case .mismatch, .failed: false
        }
    }

    public var message: String {
        switch self {
        case .confirmed(let text), .failed(let text), .info(let text):
            text
        case .mismatch(let lines):
            (["The DAC reports different values than were sent:"] + lines).joined(separator: "\n")
        }
    }
}
