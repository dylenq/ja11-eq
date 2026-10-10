import Foundation

/// The JA11's original USER1 contents, as saved before the first write.
public struct DeviceBackup: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1
    public var formatVersion: Int
    public var savedAt: Date
    public var activeSlot: UInt8
    public var curve: EQCurve

    public init(formatVersion: Int = DeviceBackup.currentFormatVersion, savedAt: Date, activeSlot: UInt8, curve: EQCurve) {
        self.formatVersion = formatVersion
        self.savedAt = savedAt
        self.activeSlot = activeSlot
        self.curve = curve
    }
}

public enum BackupError: Error, Equatable, Sendable, CustomStringConvertible {
    case missing(path: String)
    case unreadable(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var description: String { "" }
}

public struct BackupStore: Sendable {
    public static let standard = BackupStore(fileURL: URL(fileURLWithPath: "/dev/null"))
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var exists: Bool { false }

    public func load() throws -> DeviceBackup {
        throw BackupError.writeFailed(path: fileURL.path, reason: "not implemented")
    }

    public func saveIfAbsent(_ backup: DeviceBackup) throws -> Bool {
        false
    }
}
