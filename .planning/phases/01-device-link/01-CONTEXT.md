# Phase 1: Device Link - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Source:** Approved implementation plan (`~/.claude/plans/i-have-connected-a-agile-treasure.md`), captured the same way as the PRD Express Path. Device facts and the full protocol are in `.planning/PROJECT.md` § Context.

<domain>
## Phase Boundary

Phase 1 delivers the read-only link to the dongle: a Swift package whose `JA11Kit` library can find the FiiO JadeAudio JA11 over USB HID, follow unplug/replug, and read its active preset slot, pre-gain and filters; plus a `ja11-probe` command-line tool that prints that state.

Nothing in this phase changes the DAC. No SET (`AA 0A`) frame is built or sent. The first write happens in Phase 2.

The real JA11 is plugged into the development Mac, so every success criterion is checked against hardware, not a mock.

</domain>

<decisions>
## Implementation Decisions

### Package
- **D-01:** One dependency-free Swift package at the repo root: `Package.swift` declaring library target `JA11Kit`, executable target `ja11-probe`, test target `JA11KitTests`. Platform `macOS 14` or later. No third-party packages.
- **D-02:** Source layout:
  - `Sources/JA11Kit/Protocol/FiioFrame.swift` — frame building and reply parsing, big-endian int16/uint16 scaling
  - `Sources/JA11Kit/Protocol/JA11Commands.swift` — command IDs, slot IDs, device limits, VID/PID, report ID
  - `Sources/JA11Kit/HID/HIDTransport.swift` — IOHIDManager wrapper
  - `Sources/JA11Kit/Device/JA11Device.swift` — async read API on top of the transport
  - `Sources/JA11Kit/Model/EQModel.swift` — `FilterType`, `Band`, `EQState`, preset slot type
  - `Sources/ja11-probe/main.swift` — the CLI
  - `Tests/JA11KitTests/` — unit tests that run without the device

### Protocol codec
- **D-03:** GET request frame is `BB 0B 00 00 <cmd> <len> <data…> 00 EE`, sent as HID output report ID `0x02`. Primary form: zero-padded to the full 20-byte report length the descriptor declares. Permitted fallback, used only if the dongle does not answer the padded form: the same frame unpadded (8–9 bytes), which is what the reference implementation sends through WebHID on macOS. Both forms are read-only GET requests; no other variation (header, command byte, report ID, extra bytes) is allowed. The form the device answers is the one used from then on. Reference GET frames (before padding): slot `BB 0B 00 00 16 00 00 EE`, filter count `BB 0B 00 00 18 00 00 EE`, pre-gain `BB 0B 00 00 17 00 00 EE`, filter N `BB 0B 00 00 15 01 <N> 00 EE`.
- **D-04:** This phase implements GET request encoding and reply parsing only. SET (`AA 0A`) encoding is deliberately left to Phase 2, so no code path in Phase 1 can change the DAC.
- **D-05:** Replies are recognised by header `BB 0B` with the command at byte 4 and data from byte 6. Decoding: slot = byte 6 (`0` Vocal, `1` Classic, `2` Bass, `3` USER1, `4` EQ off); filter count = byte 6; pre-gain = int16 big-endian at bytes 6–7, two's complement, ÷ 10 dB; filter = index at byte 6, gain int16 BE at 7–8 ÷ 10 dB, frequency uint16 BE at 9–10 in Hz, Q uint16 BE at 11–12 ÷ 100, type at byte 13 (`0` peak, `1` low shelf, `2` high shelf).
- **D-06:** macOS may hand input reports to the callback with or without a leading report-ID byte. The parser must locate the `BB 0B` header at offset 0 or 1 rather than assume one layout, and the layout actually seen on the device is recorded in the phase summary.

### HID transport
- **D-07:** Use IOKit `IOHIDManager`, matching vendor ID `0x2972` and product ID `0x0102`. No manual device selection.
- **D-08:** Open the device with `kIOHIDOptionsTypeNone` — never `kIOHIDOptionsTypeSeizeDevice` — so the dongle's volume and play/pause buttons keep reaching macOS.
- **D-09:** Hotplug comes from the manager's device-matching and device-removal callbacks; the transport reports connected/disconnected to its owner and survives any number of unplug/replug cycles without being recreated.
- **D-10:** If opening the device fails with a not-permitted / not-privileged IOKit result, surface a dedicated error whose message tells the user to enable the running program under System Settings → Privacy & Security → Input Monitoring. Other failures keep their IOKit code in the message.

### Reading state
- **D-11:** Read sequence: slot (`0x16`), filter count (`0x18`), pre-gain (`0x17`), then one filter request (`0x15`) per index `0 ..< count`. Each request waits for its matching reply with a timeout; a missing reply produces a distinct "device did not answer" error rather than a hang or zeros.
- **D-12:** `JA11Device` in this phase exposes read operations only.

### Probe CLI
- **D-13:** `ja11-probe` with no arguments finds the dongle, prints slot name, pre-gain and every filter (index, type, frequency in Hz, gain in dB, Q), then exits `0`. If no JA11 is connected it prints a clear message and exits non-zero.
- **D-14:** `ja11-probe --watch` stays running, prints a line on disconnect and on connect, and re-reads and prints the state on each connect.
- **D-15:** `ja11-probe --raw` additionally prints every frame sent and received as hex, to settle the open device questions.

### Evidence
- **D-16:** The phase summary records what the real device showed for the open questions this phase can answer: whether the JA11 replies to GET requests, which frame form it answered (padded or unpadded, D-03), whether macOS demanded Input Monitoring, and whether input reports carry a leading report-ID byte.

### Claude's Discretion
- Concurrency design (run loop vs. dispatch queue for HID callbacks, actor vs. class, how replies are awaited)
- Swift Testing vs. XCTest
- Exact type and method names beyond the files and targets fixed above
- Exact wording and layout of probe output
- Timeout length for replies (order of one second)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Device and protocol
- `.planning/PROJECT.md` — § Context holds the observed USB/HID facts, the decoded report descriptor, the full FiiO framed protocol and the open device questions; § Constraints holds the safety rules
- External reference implementation (0BSD): `github.com/jeromeof/devicePEQ`, file `devicePEQ/fiioUsbHidHandler.js`, and the `"JadeAudio JA11"` entry in `devicePEQ/usbDeviceConfig.js` (report ID 2, slots, `disconnectOnSave`)

### Scope
- `.planning/ROADMAP.md` — Phase 1 goal and five success criteria
- `.planning/REQUIREMENTS.md` — LINK-01 … LINK-06

</canonical_refs>

<specifics>
## Specific Ideas

- Device identity as enumerated on this Mac: product string `JadeAudio JA11`, manufacturer `FIIO`, HID top-level usage Consumer Control (page `0x0C`, usage `0x01`), max input and output report size 21 bytes (20 payload + report ID).
- Output report `0x02` carries exactly 20 payload bytes; input report `0x02` likewise. Reports `0x4B` and `0x54` (chip vendor channel) must never be written.
- Toolchain on this Mac: Swift 6.4 (Xcode), macOS 27, Apple silicon. `swift build`, `swift test`, `swift run ja11-probe` are the working commands.
- Unit tests must cover: GET frame bytes for each command against the reference frames in D-03, reply parsing for slot / count / pre-gain / filter, negative gain decoding (e.g. `FF C4` → −6.0 dB), and the header-at-offset-0-or-1 rule in D-06.

</specifics>

<deferred>
## Deferred Ideas

- SET frame encoding, writing a curve, saving to USER1, slot switching, backup/restore — Phase 2
- Biquad response math and auto pre-gain — Phase 2
- SwiftUI window, graph, sample-rate readout — Phase 3
- `.app` bundle and README — Phase 4

</deferred>

---

*Phase: 01-device-link*
*Context gathered: 2026-10-10 from the approved implementation plan*
