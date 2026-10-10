import Foundation
import JA11Kit

/// The single fallback text for an unknown preset or a missing sample rate: an em dash.
public let missingValueText = "\u{2014}"

/// What the user sees about the link to the JA11. Exactly three states.
public enum ConnectionStatus: Equatable, Sendable {
    case notConnected
    case connected
    /// macOS refused access; the text is the error's description.
    case accessRefused(String)

    public var title: String {
        switch self {
        case .notConnected: "Not connected"
        case .connected: "Connected"
        case .accessRefused: "Access refused"
        }
    }

    public var detail: String? {
        switch self {
        case .notConnected: "Plug in the JA11"
        case .connected: nil
        case .accessRefused(let text): text
        }
    }
}

/// The presets the user can pick from. The Custom preset is the dongle's USER1 slot.
public enum PresetChoice: CaseIterable, Sendable {
    case vocal, classic, bass, custom, off

    public var slot: PresetSlot {
        switch self {
        case .vocal: .vocal
        case .classic: .classic
        case .bass: .bass
        case .custom: .user1
        case .off: .off
        }
    }

    public var title: String {
        switch self {
        case .vocal: "Vocal"
        case .classic: "Classic"
        case .bass: "Bass"
        case .custom: "Custom"
        case .off: "Off"
        }
    }

    /// Only Custom (USER1) may be edited or written.
    public var isEditable: Bool { self == .custom }

    public init?(slotID: UInt8) {
        guard let choice = Self.allCases.first(where: { $0.slot.rawValue == slotID }) else { return nil }
        self = choice
    }
}
