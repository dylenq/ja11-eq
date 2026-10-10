import Foundation

/// The JA11's original USER1 contents, as saved before the first write (CONTEXT D-13).
///
/// The JSON keys are `formatVersion`, `savedAt`, `activeSlot` and `curve`. A file written once has
/// to stay readable by every later version of this library.
public struct DeviceBackup: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// When the backup was taken, to the second.
    public var savedAt: Date
    /// The slot that was active when the backup was taken.
    public var activeSlot: UInt8
    /// USER1's contents: pre-gain and five bands.
    public var curve: EQCurve

    public init(
        formatVersion: Int = DeviceBackup.currentFormatVersion,
        savedAt: Date,
        activeSlot: UInt8,
        curve: EQCurve
    ) {
        self.formatVersion = formatVersion
        self.savedAt = savedAt
        self.activeSlot = activeSlot
        self.curve = curve
    }
}

/// Why the backup file could not be used.
public enum BackupError: Error, Equatable, Sendable, CustomStringConvertible {
    /// There is no backup file.
    case missing(path: String)
    /// There is a file, but it does not hold a backup this library can use. It was not changed.
    case unreadable(path: String, reason: String)
    /// The backup could not be written.
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .missing(let path):
            "No backup of the original USER1 found at \(path)."
        case .unreadable(let path, let reason):
            "The backup at \(path) cannot be read (\(reason)). It was left untouched; nothing was written to the JA11."
        case .writeFailed(let path, let reason):
            "Could not write the backup to \(path) (\(reason))."
        }
    }
}

/// The one file that holds the dongle's original USER1 contents.
///
/// The file is written once. This type can create it and read it, and nothing else: it has no way
/// to replace, change or delete a file that exists, whatever that file holds.
public struct BackupStore: Sendable {
    /// `~/Library/Application Support/JA11 EQ/user1-original.json`
    public static let standard = BackupStore(
        fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JA11 EQ", isDirectory: true)
            .appendingPathComponent("user1-original.json", isDirectory: false)
    )

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Whether something is at the file's place. It says nothing about whether it can be read.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// The backup in the file.
    ///
    /// Throws `.missing` when there is no file and `.unreadable` when the file does not decode,
    /// has another format version, names a slot above 4 or does not hold exactly five bands.
    public func load() throws -> DeviceBackup {
        let path = fileURL.path
        guard exists else { throw BackupError.missing(path: path) }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw BackupError.unreadable(path: path, reason: error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // The version is looked at on its own first, so a later format is named as what it is.
        struct Version: Decodable { let formatVersion: Int }
        let backup: DeviceBackup
        do {
            let version = try decoder.decode(Version.self, from: data).formatVersion
            guard version == DeviceBackup.currentFormatVersion else {
                throw BackupError.unreadable(
                    path: path,
                    reason: "format version \(version), expected \(DeviceBackup.currentFormatVersion)"
                )
            }
            backup = try decoder.decode(DeviceBackup.self, from: data)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.unreadable(path: path, reason: "not a backup file: \(Self.reason(for: error))")
        }

        guard PresetSlot(rawValue: backup.activeSlot) != nil else {
            throw BackupError.unreadable(path: path, reason: "active slot \(backup.activeSlot) is not a slot of the JA11")
        }
        guard backup.curve.bands.count == JA11Limits.maxBands else {
            throw BackupError.unreadable(
                path: path,
                reason: "\(backup.curve.bands.count) bands, expected \(JA11Limits.maxBands)"
            )
        }
        return backup
    }

    /// Writes `backup` unless a file is already there.
    ///
    /// Returns true when the file was written and false when one existed; that one is kept as it
    /// is. The backup is first written in full to a temporary file in the same directory, and the
    /// final name is then made with `link`, which fails when the name exists and never replaces
    /// it. So the file is either complete or absent, and of several writers exactly one wins.
    public func saveIfAbsent(_ backup: DeviceBackup) throws -> Bool {
        let path = fileURL.path
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".user1-original-\(UUID().uuidString).tmp", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backup)

            // The temporary file goes away in every case; the final name, once made, stays.
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()

            if link(temporary.path, path) == 0 { return true }
            let code = errno
            if code == EEXIST { return false }
            throw BackupError.writeFailed(path: path, reason: String(cString: strerror(code)))
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.writeFailed(path: path, reason: error.localizedDescription)
        }
    }

    private static func reason(for error: any Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .dataCorrupted(let context), .keyNotFound(_, let context),
             .typeMismatch(_, let context), .valueNotFound(_, let context):
            return context.debugDescription
        @unknown default:
            return String(describing: decoding)
        }
    }
}
