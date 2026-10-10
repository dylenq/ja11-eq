import Foundation
import JA11Kit

// Lines appear as they are printed, also when stdout is a pipe or a file.
setvbuf(stdout, nil, _IOLBF, 0)

/// Exit statuses of the command. 0 to 4 mean what they mean for `ja11-probe`.
enum ExitStatus {
    /// The operation was confirmed by read-back; for `backup`: the backup exists and was printed.
    static let confirmed: Int32 = 0
    static let notFound: Int32 = 1
    /// Also an unreadable curve file.
    static let usageError: Int32 = 2
    static let accessRefused: Int32 = 3
    static let operationFailed: Int32 = 4
    static let mismatch: Int32 = 5
    static let backupProblem: Int32 = 6
}

/// The slot names the command line accepts, exactly as written here.
let slotNames: [(name: String, slot: PresetSlot)] = [
    ("vocal", .vocal),
    ("classic", .classic),
    ("bass", .bass),
    ("user1", .user1),
    ("off", .off),
]

enum CLI {
    /// The one backup file. Naming its path creates nothing.
    static let store = BackupStore.standard

    /// A curve file larger than this is refused unread.
    static let maxCurveFileBytes = 64 * 1024

    static let usage = """
        usage: ja11-eq [--raw] <command>
          backup               save the JA11's original USER1 contents; print the backup
          apply <curve.json>   write the curve in the file to USER1 and read it back
          apply --test-curve   write the built-in test curve to USER1 and read it back
          restore              write the backed-up curve to USER1, re-select the original slot
          slot <vocal|classic|bass|user1|off>
                               make that preset the active one and read the slot back
          --raw                also print every frame sent and received as hex
          --help               show this text
        curve file: JSON, at most 5 bands, type is peak, lowShelf or highShelf:
          {"preGain": -6.0, "bands": [{"type": "peak", "frequency": 1000, "gain": -3.0, "q": 1.0}]}
        backup file: \(store.fileURL.path)
          written once, before the first write to the JA11, and never replaced
        exit status: 0 confirmed by read-back (backup: the backup was printed), 1 no JA11 found,
          2 usage error or unreadable curve file, 3 access refused by macOS,
          4 device operation failed, 5 read-back mismatch, 6 backup problem
        """
}

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Says what is wrong with the invocation, prints the usage text and ends with status 2.
func exitWithUsageError(_ message: String) -> Never {
    printError("ja11-eq: \(message)")
    printError(CLI.usage)
    exit(ExitStatus.usageError)
}

/// What the command line asks for, before the curve file is read.
enum Request {
    case backup
    case applyFile(path: String)
    case applyTestCurve
    case restore
    case slot(PresetSlot)
}

/// What the command is to do, with everything it needs: nothing is left to check.
enum Operation {
    case backup
    case apply(EQCurve)
    case applyTestCurve
    case restore
    case slot(PresetSlot)
}

/// The parsed command: the operation and the raw flag.
struct Invocation {
    let operation: Operation
    let raw: Bool
}

struct UsageError: Error {
    let message: String
}

/// The request the words after the flags describe.
///
/// A slot is one of the five lowercase names, compared as exact strings: a number, a capital
/// letter or any other word is not a slot.
func parseRequest(_ words: [String]) throws -> Request {
    guard let subcommand = words.first else {
        throw UsageError(message: "no command given")
    }
    let rest = Array(words.dropFirst())

    switch subcommand {
    case "backup", "restore":
        guard rest.isEmpty else {
            throw UsageError(message: "'\(subcommand)' takes no argument, got '\(rest[0])'")
        }
        return subcommand == "backup" ? .backup : .restore

    case "apply":
        guard let first = rest.first else {
            throw UsageError(message: "'apply' needs a curve file or --test-curve")
        }
        guard rest.count == 1 else {
            throw UsageError(message: "'apply' takes one curve file or --test-curve, nothing more; got '\(rest[1])' as well")
        }
        if first == "--test-curve" { return .applyTestCurve }
        guard !first.hasPrefix("-") else {
            throw UsageError(message: "unknown option '\(first)'")
        }
        return .applyFile(path: first)

    case "slot":
        let names = slotNames.map(\.name).joined(separator: ", ")
        guard let first = rest.first else {
            throw UsageError(message: "'slot' needs a slot name: \(names)")
        }
        guard rest.count == 1 else {
            throw UsageError(message: "'slot' takes one slot name, got '\(rest[1])' as well")
        }
        guard let slot = slotNames.first(where: { $0.name == first })?.slot else {
            throw UsageError(message: "'\(first)' is not a slot name; expected one of: \(names)")
        }
        return .slot(slot)

    default:
        if subcommand.hasPrefix("-") {
            throw UsageError(message: "unknown option '\(subcommand)'")
        }
        throw UsageError(message: "unknown command '\(subcommand)'")
    }
}

struct CurveFileError: Error {
    let reason: String
}

/// The curve in the file at `path`. The path is only ever read.
///
/// Refused: anything that is not a regular file, a file larger than 64 KB, a file that does not
/// decode as a curve, and a curve with more bands than the JA11 has.
func loadCurve(atPath path: String) throws -> EQCurve {
    var info = stat()
    guard stat(path, &info) == 0 else {
        throw CurveFileError(reason: String(cString: strerror(errno)))
    }
    guard (info.st_mode & S_IFMT) == S_IFREG else {
        throw CurveFileError(reason: "not a regular file")
    }
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw CurveFileError(reason: "the file cannot be opened")
    }
    defer { try? handle.close() }

    // One byte more than the limit is asked for, so a longer file shows without being read whole.
    let data: Data
    do {
        data = try handle.read(upToCount: CLI.maxCurveFileBytes + 1) ?? Data()
    } catch {
        throw CurveFileError(reason: error.localizedDescription)
    }
    guard data.count <= CLI.maxCurveFileBytes else {
        throw CurveFileError(reason: "larger than 64 KB")
    }

    let curve: EQCurve
    do {
        curve = try JSONDecoder().decode(EQCurve.self, from: data)
    } catch {
        throw CurveFileError(reason: decodingReason(for: error))
    }
    guard curve.bands.count <= JA11Limits.maxBands else {
        throw CurveFileError(reason: "\(curve.bands.count) bands, the JA11 has \(JA11Limits.maxBands)")
    }
    return curve
}

func decodingReason(for error: any Error) -> String {
    guard let decoding = error as? DecodingError else { return error.localizedDescription }
    switch decoding {
    case .dataCorrupted(let context), .keyNotFound(_, let context),
         .typeMismatch(_, let context), .valueNotFound(_, let context):
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    @unknown default:
        return String(describing: decoding)
    }
}

// Every argument, and the curve file, is checked before a transport or a device object exists: a
// usage error, `--help` or an unreadable curve file never touches the device.
var raw = false
var help = false
var words: [String] = []
for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--raw":
        raw = true
    case "--help":
        help = true
    default:
        words.append(argument)
    }
}

// `--help` on its own is not an error; next to anything invalid, the error wins.
if help, words.isEmpty {
    print(CLI.usage)
    exit(ExitStatus.confirmed)
}

let request: Request
do {
    request = try parseRequest(words)
} catch let error as UsageError {
    exitWithUsageError(error.message)
} catch {
    exitWithUsageError(String(describing: error))
}

if help {
    print(CLI.usage)
    exit(ExitStatus.confirmed)
}

let operation: Operation
switch request {
case .backup:
    operation = .backup
case .applyTestCurve:
    operation = .applyTestCurve
case .restore:
    operation = .restore
case .slot(let slot):
    operation = .slot(slot)
case .applyFile(let path):
    do {
        operation = .apply(try loadCurve(atPath: path))
    } catch {
        let reason = (error as? CurveFileError)?.reason ?? String(describing: error)
        printError("ja11-eq: cannot read curve file '\(path)': \(reason)")
        exit(ExitStatus.usageError)
    }
}

let invocation = Invocation(operation: operation, raw: raw)

// The backup file is looked at before a transport exists as well. A file that is there but cannot
// be read stops every command, and a restore needs the file. `backup` with a file already there
// needs no device at all: it prints the file and ends.
do {
    switch invocation.operation {
    case .backup:
        if CLI.store.exists {
            let backup = try CLI.store.load()
            printBackupLine(saved: false)
            printBackupDetails(backup)
            exit(ExitStatus.confirmed)
        }
    case .restore:
        _ = try CLI.store.load()
        printBackupLine(saved: false)
    case .apply, .applyTestCurve, .slot:
        if CLI.store.exists {
            _ = try CLI.store.load()
        }
    }
} catch {
    printError(errorText(error))
    exit(exitStatus(for: error))
}

// `--raw` changes what is printed, never what is sent. Every write goes through the writer, which
// sees to the backup first; this file builds no frame and calls no other write function.
let device = JA11Device(transport: HIDTransport(), trace: invocation.raw ? makeRawTrace() : nil)
let writer = JA11Writer(device: device, store: CLI.store)

do {
    await device.start()
    try await device.waitForConnection()

    switch invocation.operation {
    case .backup:
        let outcome = try await writer.backup()
        printBackupLine(outcome)
        printBackupDetails(outcome.backup)
        exit(ExitStatus.confirmed)

    case .apply(let curve):
        printBackupLine(try await writer.backup())
        let report = try await writer.apply(curve)
        printApply(report)
        exitWithResult(isConfirmed: report.isConfirmed)

    case .applyTestCurve:
        printBackupLine(try await writer.backup())
        let report = try await writer.applyTestCurve()
        printApply(report)
        exitWithResult(isConfirmed: report.isConfirmed)

    case .restore:
        let report = try await writer.restore()
        printApply(report.apply)
        if report.finalSlotID != report.expectedSlotID {
            print("diff: final slot: expected \(slotText(report.expectedSlotID)), read \(slotText(report.finalSlotID))")
        }
        print("final: slot: \(slotText(report.finalSlotID))")
        exitWithResult(isConfirmed: report.isConfirmed)

    case .slot(let slot):
        printBackupLine(try await writer.backup())
        let report = try await writer.selectSlot(slot)
        print("sent: slot: \(slotText(report.requested.rawValue))")
        print("read: slot: \(slotText(report.readSlotID))")
        // What the device holds in this slot, as far as it lets itself be read. Not being able to
        // read it is information, not a failure of the switch.
        do {
            for line in try await device.readState().reportLines() {
                print("state: " + line)
            }
        } catch {
            print("info: state not readable in this slot: \(errorText(error))")
        }
        exitWithResult(isConfirmed: report.isConfirmed)
    }
} catch {
    printError(errorText(error))
    exit(exitStatus(for: error))
}

// MARK: - Output

/// `backup: saved <path>` when this run created the file, `backup: kept <path>` when it was there.
func printBackupLine(saved: Bool) {
    print("backup: \(saved ? "saved" : "kept") \(CLI.store.fileURL.path)")
}

func printBackupLine(_ outcome: BackupOutcome) {
    switch outcome {
    case .created: printBackupLine(saved: true)
    case .kept: printBackupLine(saved: false)
    }
}

/// When the backup was taken, and USER1's original contents with the slot that was active then.
func printBackupDetails(_ backup: DeviceBackup) {
    print("backup-time: \(ISO8601DateFormatter().string(from: backup.savedAt))")
    var original = backup.curve.deviceState()
    original.slotID = backup.activeSlot
    for line in original.reportLines() {
        print("original: " + line)
    }
}

/// What an apply sent, what the link did after the save, what was read back and how it differs.
func printApply(_ report: ApplyReport) {
    for line in report.sent.reportLines() {
        print("sent: " + line)
    }
    for event in report.linkEvents {
        let kind = switch event.kind {
        case .disconnected: "disconnected"
        case .connected: "connected"
        }
        print("link: \(kind) \(String(format: "%+.2f", event.secondsAfterSave))s")
    }
    for line in report.readBack.reportLines() {
        print("read: " + line)
    }
    for line in report.differences {
        print("diff: " + line)
    }
}

/// The one place a result line is printed. `isConfirmed` comes from a report's own `isConfirmed`,
/// so nothing is called confirmed that the read-back does not confirm.
func exitWithResult(isConfirmed: Bool) -> Never {
    if isConfirmed {
        print("result: confirmed")
        exit(ExitStatus.confirmed)
    }
    print("result: mismatch")
    exit(ExitStatus.mismatch)
}

func slotText(_ id: UInt8) -> String {
    "\(id) (\(PresetSlot(rawValue: id)?.displayName ?? "unknown"))"
}

func errorText(_ error: any Error) -> String {
    if let error = error as? JA11Error { return error.description }
    if let error = error as? BackupError { return error.description }
    return String(describing: error)
}

/// The exit status that tells a script why the operation was not confirmed.
func exitStatus(for error: any Error) -> Int32 {
    if error is BackupError { return ExitStatus.backupProblem }
    switch error as? JA11Error {
    case .notFound: return ExitStatus.notFound
    case .transport(.accessDenied): return ExitStatus.accessRefused
    default: return ExitStatus.operationFailed
    }
}

/// The `--raw` trace: one `tx:` line per frame handed to the transport and one `rx:` line per
/// input report as delivered.
func makeRawTrace() -> @Sendable (FrameDirection, [UInt8]) -> Void {
    { direction, bytes in
        switch direction {
        case .sent: print("tx: " + FiioFrame.hex(bytes))
        case .received: print("rx: " + FiioFrame.hex(bytes))
        }
    }
}
