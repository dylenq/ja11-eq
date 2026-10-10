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

// The part that opens the device and runs the operation follows in the next commit of this plan.
// Until then a valid command ends here, before any transport exists.
_ = invocation
printError("ja11-eq: this build checks the command line only; nothing was sent to the JA11.")
exit(ExitStatus.operationFailed)
