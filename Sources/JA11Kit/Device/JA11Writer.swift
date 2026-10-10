import Foundation

/// What `JA11Writer.backup()` found or did.
public enum BackupOutcome: Sendable, Equatable {
    /// There was no backup file; the device was read and the file written.
    case created(DeviceBackup)
    /// A backup file was already there; it was kept and the device was not touched.
    case kept(DeviceBackup)

    /// The backup that is on disk now.
    public var backup: DeviceBackup {
        switch self {
        case .created(let backup), .kept(let backup): backup
        }
    }
}

/// The outcome of a preset switch: the slot asked for and the slot the device reports afterwards.
public struct SlotReport: Sendable, Equatable {
    public let requested: PresetSlot
    public let readSlotID: UInt8

    /// True only when the device reports the slot that was asked for.
    public var isConfirmed: Bool {
        readSlotID == requested.rawValue
    }
}

/// The outcome of a restore.
public struct RestoreReport: Sendable, Equatable {
    /// The apply of the backed-up curve to USER1.
    public let apply: ApplyReport
    /// The slot recorded in the backup.
    public let expectedSlotID: UInt8
    /// The slot the device reports at the end.
    public let finalSlotID: UInt8

    /// True only when the curve read back as sent and the device is in the slot the backup names.
    public var isConfirmed: Bool {
        apply.isConfirmed && finalSlotID == expectedSlotID
    }
}

/// The one public way to write to the JA11 (CONTEXT D-11, D-13, D-14).
///
/// Every operation that makes the device write first sees to it that the backup of the original
/// USER1 contents is on disk. A backup file that exists but cannot be read ends the operation
/// before anything is sent. Nothing here saves to any slot but USER1.
public struct JA11Writer: Sendable {
    private let device: JA11Device
    private let store: BackupStore

    public init(device: JA11Device, store: BackupStore = .standard) {
        self.device = device
        self.store = store
    }

    /// Makes sure the backup file exists.
    ///
    /// With a file already there, the file is loaded and the device is not touched. Otherwise
    /// USER1's contents are read from the device and written to the file.
    public func backup() async throws -> BackupOutcome {
        if store.exists {
            return .kept(try store.load())
        }
        let backup = try await device.captureUser1()
        if try store.saveIfAbsent(backup) {
            return .created(backup)
        }
        // Another writer was faster; its file is the backup.
        return .kept(try store.load())
    }

    /// Writes `curve` to USER1 and reads the device back. The backup is taken first.
    public func apply(_ curve: EQCurve) async throws -> ApplyReport {
        _ = try await backup()
        return try await device.apply(curve)
    }

    /// Applies the built-in test curve, built on the backed-up contents of USER1.
    public func applyTestCurve() async throws -> ApplyReport {
        let original = try await backup().backup
        return try await device.apply(EQCurve.testCurve(basedOn: original.curve))
    }

    /// Writes the backed-up curve to USER1 and re-selects the slot that was active at backup time.
    ///
    /// Throws `BackupError.missing` or `.unreadable` before anything is sent. When the apply is
    /// not confirmed, nothing further is sent.
    public func restore() async throws -> RestoreReport {
        let backup = try store.load()
        let report = try await device.apply(backup.curve)

        var finalSlotID = report.readBack.slotID
        if report.isConfirmed,
           backup.activeSlot != JA11SlotID.user1,
           let slot = PresetSlot(rawValue: backup.activeSlot) {
            finalSlotID = try await device.selectSlot(slot)
        }
        return RestoreReport(apply: report, expectedSlotID: backup.activeSlot, finalSlotID: finalSlotID)
    }

    /// Makes `slot` the active preset and reports the slot read back. The backup is taken first:
    /// a preset switch is a write too.
    public func selectSlot(_ slot: PresetSlot) async throws -> SlotReport {
        _ = try await backup()
        return SlotReport(requested: slot, readSlotID: try await device.selectSlot(slot))
    }
}
