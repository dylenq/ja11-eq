import Foundation
import Testing
@testable import JA11Kit

/// The backup file: written once, complete or absent, never replaced (CONTEXT D-13).
///
/// Every test works in a fresh directory under the temporary directory and removes it afterwards.
/// None reads or writes the real Application Support location.
@Suite struct BackupStoreTests {
    // MARK: - Helpers

    /// Runs `body` with a store in a directory that does not exist yet, then removes the directory.
    static func withStore<T>(_ body: (BackupStore, URL) async throws -> T) async rethrows -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ja11-backup-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(fileURL: directory.appendingPathComponent("user1-original.json"))
        return try await body(store, directory)
    }

    /// A backup of the dongle's original USER1 contents; `preGain` tells two backups apart.
    static func backup(preGain: Double = 0.0, activeSlot: UInt8 = JA11SlotID.user1) -> DeviceBackup {
        var curve = EQCurve(state: EQState(slotID: 3, preGain: preGain, bands: FakeDongle.originalBands))!
        curve.preGain = preGain
        return DeviceBackup(
            savedAt: Date(timeIntervalSince1970: 1_791_000_000),
            activeSlot: activeSlot,
            curve: curve
        )
    }

    /// A backup file as text, written by hand so the shape on disk is pinned.
    static func json(formatVersion: Int = 1, activeSlot: Int = 3, bandCount: Int = 5) -> String {
        let band = #"{"type":"lowShelf","frequency":59,"gain":0,"q":0.7,"enabled":true}"#
        let bands = Array(repeating: band, count: bandCount).joined(separator: ",")
        return #"{"formatVersion":\#(formatVersion),"savedAt":"2026-10-10T12:00:00Z","#
            + #""activeSlot":\#(activeSlot),"curve":{"preGain":-1.5,"bands":[\#(bands)]}}"#
    }

    /// Puts `text` where the store's file belongs, creating the directory.
    static func write(_ text: String, to store: BackupStore) throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: store.fileURL)
    }

    static func entries(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    static func loadError(_ store: BackupStore) -> BackupError? {
        do {
            _ = try store.load()
            return nil
        } catch {
            return error as? BackupError
        }
    }

    static func isUnreadable(_ error: BackupError?) -> Bool {
        if case .unreadable = error { return true }
        return false
    }

    static func isMissing(_ error: BackupError?) -> Bool {
        if case .missing = error { return true }
        return false
    }

    // MARK: - Location

    @Test func theStandardStoreIsInTheUsersApplicationSupportDirectory() {
        let path = BackupStore.standard.fileURL.path
        #expect(path.hasSuffix("/Library/Application Support/JA11 EQ/user1-original.json"))
    }

    // MARK: - Saving

    @Test func saveCreatesTheDirectoryAndTheFileAndLoadReturnsAnEqualBackup() async throws {
        try await Self.withStore { store, directory in
            let backup = Self.backup(preGain: -2.5, activeSlot: 1)

            #expect(!store.exists)
            let written = try store.saveIfAbsent(backup)
            #expect(written)
            #expect(store.exists)

            #expect(try store.load() == backup)
            #expect(try Self.entries(in: directory) == ["user1-original.json"])
        }
    }

    @Test func aSecondSaveReturnsFalseAndLeavesTheFileUnchanged() async throws {
        try await Self.withStore { store, directory in
            #expect(try store.saveIfAbsent(Self.backup(preGain: -1.0)))
            let bytes = try Data(contentsOf: store.fileURL)

            #expect(try store.saveIfAbsent(Self.backup(preGain: -9.0)) == false)

            #expect(try Data(contentsOf: store.fileURL) == bytes)
            #expect(try store.load() == Self.backup(preGain: -1.0))
            #expect(try Self.entries(in: directory).count == 1)
        }
    }

    @Test func theFileIsJSONWithTheFourKeys() async throws {
        try await Self.withStore { store, _ in
            #expect(try store.saveIfAbsent(Self.backup(activeSlot: 2)))

            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL))
            let fields = try #require(object as? [String: Any])
            #expect(Set(fields.keys) == ["formatVersion", "savedAt", "activeSlot", "curve"])
            #expect(fields["formatVersion"] as? Int == 1)
            #expect(fields["activeSlot"] as? Int == 2)
            #expect(fields["savedAt"] as? String == "2026-10-03T04:00:00Z")
            let curve = try #require(fields["curve"] as? [String: Any])
            #expect((curve["bands"] as? [Any])?.count == 5)
        }
    }

    @Test func twentyConcurrentSavesLeaveExactlyOneWritersBackup() async throws {
        try await Self.withStore { store, directory in
            let winners = await withTaskGroup(of: Int?.self) { group in
                for writer in 0..<20 {
                    group.addTask {
                        (try? store.saveIfAbsent(Self.backup(preGain: -Double(writer) / 10))) == true ? writer : nil
                    }
                }
                var winners: [Int] = []
                for await winner in group {
                    if let winner { winners.append(winner) }
                }
                return winners
            }

            #expect(winners.count == 1)
            let winner = try #require(winners.first)
            #expect(try store.load() == Self.backup(preGain: -Double(winner) / 10))
            #expect(try Self.entries(in: directory) == ["user1-original.json"])
        }
    }

    // MARK: - Loading

    @Test func loadWithoutAFileThrowsMissing() async throws {
        await Self.withStore { store, _ in
            #expect(Self.isMissing(Self.loadError(store)))
            #expect(!store.exists)
        }
    }

    @Test func aFileWrittenByHandInThePinnedShapeLoads() async throws {
        try await Self.withStore { store, _ in
            try Self.write(Self.json(), to: store)

            let backup = try store.load()

            #expect(backup.formatVersion == 1)
            #expect(backup.activeSlot == 3)
            #expect(backup.savedAt == Date(timeIntervalSince1970: 1_791_633_600))
            #expect(backup.curve.preGain == -1.5)
            #expect(backup.curve.bands.count == 5)
            #expect(backup.curve.bands[0] == EQBand(type: .lowShelf, frequency: 59, gain: 0.0, q: 0.7))
        }
    }

    @Test func aFileThatIsNotJSONIsUnreadableAndLeftUntouched() async throws {
        try await Self.withStore { store, directory in
            try Self.write("not json", to: store)

            #expect(Self.isUnreadable(Self.loadError(store)))
            #expect(store.exists)

            // A save does not repair it either.
            #expect(try store.saveIfAbsent(Self.backup()) == false)
            #expect(try Data(contentsOf: store.fileURL) == Data("not json".utf8))
            #expect(try Self.entries(in: directory).count == 1)
        }
    }

    @Test(arguments: [
        BackupStoreTests.json(formatVersion: 2),
        BackupStoreTests.json(bandCount: 4),
        BackupStoreTests.json(bandCount: 6),
        BackupStoreTests.json(activeSlot: 7),
        BackupStoreTests.json(activeSlot: 300),
        "{}",
        "",
    ])
    func aFileWithAnotherVersionSlotOrBandCountIsUnreadable(text: String) async throws {
        try await Self.withStore { store, _ in
            try Self.write(text, to: store)

            #expect(Self.isUnreadable(Self.loadError(store)))
            #expect(try Data(contentsOf: store.fileURL) == Data(text.utf8))
        }
    }

    // MARK: - Wording

    @Test func errorsSayWhatHappenedToTheFile() {
        #expect(BackupError.missing(path: "/x/y.json").description
            == "No backup of the original USER1 found at /x/y.json.")
        #expect(BackupError.unreadable(path: "/x/y.json", reason: "bad").description
            == "The backup at /x/y.json cannot be read (bad). It was left untouched; nothing was written to the JA11.")
        #expect(BackupError.writeFailed(path: "/x/y.json", reason: "full").description
            == "Could not write the backup to /x/y.json (full).")
    }
}
