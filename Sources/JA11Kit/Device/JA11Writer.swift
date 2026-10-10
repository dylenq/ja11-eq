import Foundation

public enum BackupOutcome: Sendable, Equatable {
    case created(DeviceBackup)
    case kept(DeviceBackup)

    public var backup: DeviceBackup {
        switch self {
        case .created(let backup), .kept(let backup): backup
        }
    }
}

public struct SlotReport: Sendable, Equatable {
    public let requested: PresetSlot
    public let readSlotID: UInt8
    public var isConfirmed: Bool { readSlotID == requested.rawValue }
}

public struct RestoreReport: Sendable, Equatable {
    public let apply: ApplyReport
    public let expectedSlotID: UInt8
    public let finalSlotID: UInt8
    public var isConfirmed: Bool { apply.isConfirmed && finalSlotID == expectedSlotID }
}

public struct JA11Writer: Sendable {
    private let device: JA11Device
    private let store: BackupStore

    public init(device: JA11Device, store: BackupStore = .standard) {
        self.device = device
        self.store = store
    }

    private var notImplemented: JA11Error { .unexpectedReply("not implemented") }

    public func backup() async throws -> BackupOutcome { throw notImplemented }
    public func apply(_ curve: EQCurve) async throws -> ApplyReport { throw notImplemented }
    public func applyTestCurve() async throws -> ApplyReport { throw notImplemented }
    public func restore() async throws -> RestoreReport { throw notImplemented }
    public func selectSlot(_ slot: PresetSlot) async throws -> SlotReport { throw notImplemented }
}
