import Foundation
import JA11Kit

// Lines appear as they are printed, also when stdout is a pipe or a file.
setvbuf(stdout, nil, _IOLBF, 0)

/// `--raw` additionally prints every frame sent and every report received, as hex.
let raw = CommandLine.arguments.dropFirst().contains("--raw")

/// One `tx:` line per frame handed to the transport, one `rx:` line per input report as delivered.
@Sendable func printFrame(_ direction: FrameDirection, _ bytes: [UInt8]) {
    switch direction {
    case .sent: print("tx: " + FiioFrame.hex(bytes))
    case .received: print("rx: " + FiioFrame.hex(bytes))
    }
}

var trace: (@Sendable (FrameDirection, [UInt8]) -> Void)?
if raw {
    trace = printFrame
}

let device = JA11Device(transport: HIDTransport(), trace: trace)

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
    exit(0)
} catch {
    let message = (error as? JA11Error)?.description ?? String(describing: error)
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
