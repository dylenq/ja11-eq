import Foundation
import JA11Kit

// Lines appear as they are printed, also when stdout is a pipe or a file.
setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
    usage: ja11-probe [--raw]
      (no arguments)  read the JA11's preset slot, pre-gain and filters once and print them
      --raw           also print every frame sent and received as hex
      --help          show this text
    exit status: 0 state printed, 1 no JA11 found, 2 usage error, 3 access refused by macOS, 4 read failed
    """

/// Exit statuses of the probe.
enum ExitStatus {
    static let statePrinted: Int32 = 0
    static let notFound: Int32 = 1
    static let usageError: Int32 = 2
    static let accessRefused: Int32 = 3
    static let readFailed: Int32 = 4
}

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// The exit status that tells a script why no state was printed.
func exitStatus(for error: any Error) -> Int32 {
    switch error as? JA11Error {
    case .notFound: ExitStatus.notFound
    case .transport(.accessDenied): ExitStatus.accessRefused
    default: ExitStatus.readFailed
    }
}

/// One `tx:` line per frame handed to the transport, one `rx:` line per input report as delivered.
@Sendable func printFrame(_ direction: FrameDirection, _ bytes: [UInt8]) {
    switch direction {
    case .sent: print("tx: " + FiioFrame.hex(bytes))
    case .received: print("rx: " + FiioFrame.hex(bytes))
    }
}

// Arguments are flags only, and they are all checked before a transport exists: a usage error or
// `--help` never touches the device.
var raw = false
var help = false
for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--raw":
        raw = true
    case "--help":
        help = true
    default:
        printError("ja11-probe: unknown argument '\(argument)'")
        printError(usage)
        exit(ExitStatus.usageError)
    }
}
if help {
    print(usage)
    exit(ExitStatus.statePrinted)
}

let device = JA11Device(transport: HIDTransport(), trace: raw ? printFrame : nil)

do {
    await device.start()
    try await device.waitForConnection()

    let state = try await device.readState()
    for line in state.reportLines() {
        print(line)
    }

    if raw, let form = await device.frameForm {
        print("info: request frame form: \(form.rawValue)")
    }
    exit(ExitStatus.statePrinted)
} catch {
    printError((error as? JA11Error)?.description ?? String(describing: error))
    exit(exitStatus(for: error))
}
