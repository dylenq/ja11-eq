---
phase: 01-device-link
plan: 01
subsystem: device-link
tags: [swift, swiftpm, iokit, hid, iohidmanager, swift-testing, usb]

# Dependency graph
requires: []
provides:
  - Swift package JA11 (library JA11Kit, executable ja11-probe, test target JA11KitTests), macOS 14+, no dependencies
  - GET-only FiiO frame codec (padded and unpadded D-03 forms) and reply decoding for slot, filter count, pre-gain and filters
  - HIDTransport (IOHIDManager, VID 0x2972 / PID 0x0102, non-exclusive) behind the ReportTransport seam
  - JA11Device actor with a read-only API (readSlot, readFilterCount, readPreGain, readFilter, readState)
  - EQ model (PresetSlot, FilterType, Band, EQState) and the probe's text output contract
  - Evidence from the real dongle for the Phase 1 open questions (D-16)
affects: [01-02, phase-2-write-path, phase-3-app-ui]

# Actuals (#2632)
actuals:
  tokens: 12749
  tasks: 2
  commits: 3
plan_head_before: 662379e0ab30a39d9625564848b04c755e991a81
plan_head_after: e14a213b6173d3234bf41b873794d4d309bca44a

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One IOHIDManager on a private serial dispatch queue; C callbacks reach the object through an Unmanaged context pointer"
    - "ReportTransport protocol as the seam between device logic and IOKit, so the device logic is testable without hardware"
    - "Actor with a single request routine: one pending expectation, reply matched by command plus an optional predicate, timeout as a cancellable task"
    - "Send gate at the transport: FiioFrame.isGetRequest decides what may reach the device"
    - "Swift Testing suite that never creates a transport"

key-files:
  created:
    - Package.swift
    - .gitignore
    - Sources/JA11Kit/Protocol/JA11Commands.swift
    - Sources/JA11Kit/Protocol/FiioFrame.swift
    - Sources/JA11Kit/HID/HIDTransport.swift
    - Sources/JA11Kit/Device/JA11Device.swift
    - Sources/JA11Kit/Model/EQModel.swift
    - Sources/ja11-probe/main.swift
    - Tests/JA11KitTests/FiioFrameTests.swift
  modified: []

key-decisions:
  - "Transport variant: the manager is opened with IOHIDManagerOpen (non-exclusive) before activation, in addition to the per-device open. As specified, without it, the manager-level input-report callback never fired."
  - "The JA11 answers GET requests, in the padded 20-byte form. The unpadded form is kept as the D-03 fallback but was never tested with a listening host."
  - "Send gate is stricter than the plan text: the length byte must be exactly what the command's request carries (1 for filter, 0 otherwise), not just 0 or 1."
  - "readFilter(index:) traps on an index outside 0..<5 instead of sending a request for a filter the device does not have."
  - "A filter reply too short to decode is reported as unexpectedReply instead of being left to time out; a decodable filter reply with another index is ignored."

patterns-established:
  - "Device values are passed on as received: an unknown slot or filter type keeps its number, nothing is defaulted"
  - "Every probe line that reports device state comes from EQState.reportLines(); --raw adds tx:/rx:/info: lines"

requirements-completed: ["LINK-01", "LINK-03", "LINK-04", "LINK-05", "LINK-06"]

coverage:
  - id: D1
    description: "ja11-probe with no arguments finds the JA11 by USB VID 0x2972 / PID 0x0102 with no selection step and exits 0"
    requirement: "LINK-01"
    verification:
      - kind: e2e
        ref: "\"$(swift build --show-bin-path)/ja11-probe\" on the real dongle: exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "ja11-probe prints the preset slot with its name, the pre-gain, the filter count and one line per filter, all decoded from replies the device sent"
    requirement: "LINK-03"
    verification:
      - kind: e2e
        ref: "plan 01-01 Task 2 verify command (slot/pre-gain/filters shape check) on the real dongle"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/FiioFrameTests.swift#reportLinesMatchTheProbeOutputContract"
        status: pass
    human_judgment: false
  - id: D3
    description: "Codec and model tests run without a transport: reference GET frames in both D-03 forms, D-05 decoding including FF C4 as -6.0 dB, D-06 header at offset 0 or 1, rejection of empty and short reports"
    requirement: "LINK-03"
    verification:
      - kind: unit
        ref: "swift test: Test run with 52 tests in 1 suite passed"
        status: pass
    human_judgment: false
  - id: D4
    description: "Nothing but GET frames for commands 0x15 to 0x18 on report 0x02 can reach the dongle: the transport refuses every other payload and holds the only output-report call"
    requirement: "LINK-04"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/FiioFrameTests.swift#gateRejectsEveryCommandByteOutsideTheFourReadCommands (and the other gate tests)"
        status: pass
      - kind: other
        ref: "! grep -rEiq '0xAA' Sources; ! grep -rEiq '0x4B|0x54' Sources; IOHIDDeviceSetReport( call sites outside comments = 1"
        status: pass
      - kind: e2e
        ref: "ja11-probe --raw: tx lines are 16, 18, 17, then 15 once per filter, all starting bb 0b; three full reads printed identical values"
        status: pass
    human_judgment: false
  - id: D5
    description: "The device is opened non-exclusively (kIOHIDOptionsTypeNone) so the dongle's volume and play/pause buttons keep reaching macOS"
    requirement: "LINK-05"
    verification:
      - kind: other
        ref: "grep -q 'kIOHIDOptionsTypeNone' Sources/JA11Kit/HID/HIDTransport.swift; ! grep -rq 'SeizeDevice' Sources"
        status: pass
    human_judgment: true
    rationale: "Whether the buttons still reach the Mac while the probe holds the device can only be confirmed by pressing them. That human check is in plan 01-02."
  - id: D6
    description: "An open refused with a not-permitted or not-privileged result becomes HIDTransportError.accessDenied, whose text names System Settings, Privacy & Security, Input Monitoring"
    requirement: "LINK-06"
    verification: []
    human_judgment: true
    rationale: "No refusal occurred in any run and one cannot be produced on demand. The classification and message are in place; their unit test and the human check are in plan 01-02."

# Metrics
duration: 14min
completed: 2026-10-10
status: complete
---

# Phase 1 Plan 01: Device Link read path Summary

**Dependency-free Swift package whose `ja11-probe` reads the JA11's preset slot, pre-gain and all five filters over IOKit HID with GET-only frames, proven on the real dongle**

## Performance

- **Duration:** 14 min (this executor run; earlier interrupted runs are not counted)
- **Started:** 2026-10-10T10:10:33Z
- **Completed:** 2026-10-10T10:24:35Z
- **Tasks:** 2 of 2
- **Files created:** 9

## Accomplishments

- `ja11-probe` finds the dongle by VID/PID, reads its EQ state with eight GET frames and prints it; exit 0.
- The riskiest open question is answered: the JA11 does answer GET requests through IOKit on this Mac.
- `JA11Kit` has the codec, the HID transport behind a protocol seam, a read-only device actor and the EQ model.
- 52 unit tests cover request building, the send gate, reply decoding and the report lines without touching IOKit.

## What the real device showed (D-16)

| Question | Observed |
|---|---|
| Does the JA11 answer GET requests? | Yes, all four commands (0x16, 0x18, 0x17, 0x15). |
| Which frame form did it answer? | **Padded** (20 bytes). `info: request frame form: padded`; one `tx:` line per request. |
| Does the unpadded form work? | Not established. It was only sent in two early runs in which no report reached the process at all (host-side cause, see below). |
| Leading report-ID byte in input reports? | Yes. Every report starts with `02`, so `headerOffset` is **1**. |
| Length of a real input report | **21 bytes** (report ID + 20). |
| Did macOS refuse the open / demand Input Monitoring? | No not-permitted or not-privileged result was ever seen. `IOHIDManagerOpen` and `IOHIDDeviceOpen` returned 0 in every run. All runs were started by the Claude Code Bash tool **inside** its sandbox; no run outside the sandbox was needed or made. This says nothing yet about a double-clicked app. |

State read from the dongle (identical in three full reads):

```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```

Frames of one `--raw` run:

```text
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
```

Two things in these frames that PROJECT.md does not describe:

- **The byte before `ee` in a reply is not `00`.** It varies per reply (`bd`, `94`, `f1`, `7f`, `6e`, `30`, `b5`, `e5`). The requests carry `00` there and are answered. Its meaning was not investigated and it is not decoded. Phase 2 should keep it in mind before assuming a SET frame may carry `00` in that position.
- **Every gain on the device is currently 0.0 dB**, pre-gain included. So the live data confirmed the positions of index, frequency, Q and type, but the sign and the x10 scale of gains are proven by unit tests only (`FF C4` gives -6.0), not by a non-zero value read from the dongle.

## Transport: which host-side variant was needed

The transport does **not** work exactly as Task 1 first specified. The variant in use:

- manager on a private serial dispatch queue: as specified
- manager-level input-report callback: as specified
- per-device `IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone)` in the matching callback: as specified, and it is what yields the open result that D-10 classifies
- **added:** `IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone)` before `IOHIDManagerSetDispatchQueue` and `IOHIDManagerActivate`

How this was found, following the plan's steps (a) to (c): with the specified arrangement the probe sent the padded and then the unpadded slot request and reported that the JA11 did not answer. Temporary logging (removed before the commit) showed open = 0, both sends = 0, and the input-report callback never called for any report ID. After adding the manager-level open the callback fired on the first request and the padded form was answered. No run-loop thread was needed. Both opens are non-exclusive, and the manager still matches on both VID and PID, so it opens nothing but the JA11.

Not yet exercised: unplug and replug. The manager stays registered and open, so a replugged dongle should arrive through the same callbacks; plan 01-02's `--watch` is what proves it.

## The send gate, for Phase 2

`HIDTransport.send` throws `.refusedFrame` for every payload that `FiioFrame.isGetRequest` rejects, takes no report-ID parameter and holds the only `IOHIDDeviceSetReport` call under `Sources/`. **No SET frame can pass it.** Phase 2 has to replace that gate deliberately when it adds writes; it cannot be bypassed by accident.

## Task Commits

1. **Task 1: End-to-end read of the active preset slot (tracer)** - `5e3a26e` (feat)
2. **Task 2: Whole EQ state, RED** - `b6833e7` (test)
3. **Task 2: Whole EQ state, GREEN** - `e14a213` (feat)

No refactor commit: nothing needed cleaning up after GREEN.

**Plan metadata:** the docs commits that follow this file (SUMMARY, then STATE/ROADMAP/REQUIREMENTS).

Tracer feedback gate after Task 1: interactive run, `human_verify_mode` = `end-of-phase`, automated-only verify. The verify was re-run and passed, so execution continued to Task 2 without a checkpoint.

## TDD (Task 2)

- **RED:** 28 tests added for the Task 2 behaviour list. Swift fails at compile time on a missing symbol, which is not a valid RED, so the RED commit also carries the new signatures with stub bodies (`nil`, `0`, `""`, `[]`) in `FiioFrame.swift` and the new `EQModel.swift`. Result: 52 tests, 33 passed, 19 failed on their assertions (for example `preGainReplyDecodesNegativeGain`: expected -6.0, got nil).
- **Evidence check:** `gsd-tools check tdd-red-evidence` on the xUnit report of that run returned `RED_EVIDENCE_OK` (`target_test_failed`). The match is at suite level (`FiioFrameTests`): the checker's name pattern picks up the `classname` attribute of Swift Testing's XML, so it cannot match a single test name there.
- **GREEN:** decoders, model behaviour, the three new reads and `readState()`; 52 of 52 pass.
- Commit order for the plan is `feat` (tracer) then `test` then `feat`. The first `feat` belongs to Task 1, which is not a TDD task.

## Files Created

- `Package.swift` - package `JA11`: library `JA11Kit`, executable `ja11-probe`, tests `JA11KitTests`; macOS 14+, no dependencies
- `.gitignore` - build output and editor files
- `Sources/JA11Kit/Protocol/JA11Commands.swift` - VID/PID, report ID, the four read command IDs, slot IDs, device limits
- `Sources/JA11Kit/Protocol/FiioFrame.swift` - GET frame building, the `isGetRequest` gate, reply location at offset 0 or 1, decoders, big-endian helpers, hex
- `Sources/JA11Kit/HID/HIDTransport.swift` - `HIDTransportError`, `ConnectionEvent`, `ReportTransport`, and the IOHIDManager wrapper
- `Sources/JA11Kit/Device/JA11Device.swift` - `JA11Error`, `FrameDirection`, the read-only device actor with the padded-then-unpadded fallback
- `Sources/JA11Kit/Model/EQModel.swift` - `PresetSlot`, `FilterType`, `Band`, `EQState.reportLines()`
- `Sources/ja11-probe/main.swift` - the probe: one read, print, `--raw` frame dump
- `Tests/JA11KitTests/FiioFrameTests.swift` - 52 codec and model tests

## Decisions Made

- **Draft adopted after review.** This run resumed an interrupted one. The eight uncommitted Task 1 files it left were read line by line against the plan. They were complete, compiled and matched the plan except for the stricter send gate below. The only source change made to that draft in Task 1 is the manager-level open in `HIDTransport.swift`.
- **Manager-level open** (see above): required for input reports to arrive.
- **Stricter send gate, kept on purpose.** See deviation 2.
- **`readFilter(index:)` traps outside `0..<5`.** See deviation 3. If a thrown error is preferred over a trap, `JA11Error` needs a new case; that is an interface change and was not made here.
- **Undecodable filter reply is an error, not a timeout.** The plan asks both that a filter reply is accepted only when its index matches and that a reply with the right command that cannot be decoded throws `unexpectedReply`. A too-short filter reply is therefore let through and reported; a decodable one with another index is ignored.
- **Count check before the pre-gain request.** A filter count above 5 ends `readState()` straight after the count reply, so neither the pre-gain nor any filter request is sent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking, permitted by Task 1 step (c)] Manager-level open added to the transport**
- **Found during:** Task 1, device check
- **Issue:** With the arrangement as first specified (no `IOHIDManagerOpen`), open and both sends returned 0 but the input-report callback never fired, so the probe reported that the JA11 did not answer.
- **Fix:** `IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone)` before the dispatch queue is set and the manager is activated. The per-device open stays.
- **Files modified:** `Sources/JA11Kit/HID/HIDTransport.swift`
- **Verification:** `ja11-probe --raw` shows one `tx:` and one `rx:` per request; exit 0
- **Committed in:** `5e3a26e`

**2. [Rule 2 - Missing critical] Send gate requires the exact data length per command**
- **Found during:** Task 1, review of the draft
- **Issue:** The plan text lets `isGetRequest` accept a length byte of 0 or 1 for any of the four commands. That would also pass frames D-03 does not list, such as a slot request carrying a data byte.
- **Fix:** Kept the draft's stricter rule: length 1 for the filter request, 0 for the other three. It accepts every frame the plan's read API builds (all eight reference frames) and nothing else. Reverting to the looser rule is a one-line change in `FiioFrame.isGetRequest`.
- **Files modified:** `Sources/JA11Kit/Protocol/FiioFrame.swift`, `Tests/JA11KitTests/FiioFrameTests.swift`
- **Verification:** `gateAcceptsAllEightReferenceRequests`, `gateRejectsADataLengthTheRequestDoesNotHave`; checked against plan 01-02, which only needs the eight reference shapes to pass
- **Committed in:** `5e3a26e`

**3. [Rule 2 - Missing critical] `readFilter(index:)` validates its index**
- **Found during:** Task 2
- **Issue:** The plan builds the request data as `[UInt8(index)]`. That traps for an index outside 0...255 and would send a request for a filter the device does not have for 5...255.
- **Fix:** `precondition` that the index is in `0..<JA11Limits.maxBands`. `readState()` never reaches it: the count is checked first.
- **Files modified:** `Sources/JA11Kit/Device/JA11Device.swift`
- **Committed in:** `e14a213`

**4. [Process] RED commit carries stub signatures**
- **Found during:** Task 2
- **Issue:** In Swift a test that names a missing symbol fails at compile time, which the TDD reference classes as an invalid RED.
- **Fix:** Signatures with stub bodies went into the `test` commit; real bodies into the `feat` commit.
- **Committed in:** `b6833e7`, `e14a213`

**5. [Scope note] Tests beyond the plan's list**
- Added because they pin boundaries the plan's rules imply: a pre-gain reply of exactly 8 bytes and a filter reply of exactly 14 bytes decode, a Q of 0 stays 0, decoders return nil for another command, display names, and gate rejections for a changed second byte, a missing terminator and a wrong data length.

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 missing critical), 2 process/scope notes
**Impact on plan:** The transport change was required for the plan's goal and stays inside what Task 1 permits. The two Rule 2 items only narrow what can be sent. No scope was added to the product.

## Issues Encountered

- **Resume state differed in one detail:** the dispatch said no commit ledger existed, but `.git/gsd-plan-head-before-01-01` was already there. It held `662379e`, which was HEAD before the first commit of this plan, so it was kept and `commits: 3` is measured from it.
- **The RED-evidence checker reads TAP or Surefire XML only.** Swift Testing's console output is neither; `swift test --xunit-output` produced a report it accepts (see TDD above).

## What was sent to the dongle

Every frame this run sent came from `FiioFrame.getRequest` through `HIDTransport.send`, by running `ja11-probe`: nine runs, 32 frames in all, each a GET request (`bb 0b`) for command 0x16, 0x18, 0x17 or 0x15 on report 0x02. Thirty were padded; two were the unpadded slot request, sent as the D-03 fallback in the two early runs where no report reached the process. No other tool, script or frame was used. What the interrupted earlier run executed is not known to this run; the code it left could not send anything but these frames.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: hid-open-scope | Sources/JA11Kit/HID/HIDTransport.swift | The manager now opens matched devices itself (`IOHIDManagerOpen`), which the threat model did not anticipate. It is bounded by the two-key VID/PID matching dictionary (T-01-03) and uses the non-exclusive option (T-01-04). |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for plan 01-02 (`FakeTransport`, device tests, `--watch`, `--help`, exit codes). `ReportTransport` is the seam for the fake.
- For 01-02: the replug path through the opened manager is still unproven; `--watch` should confirm it.
- For Phase 2: the send gate must be replaced deliberately; replies carry an undocumented byte before `ee`; gain sign and scale have not been seen in live data yet.
- No blockers.

## Self-Check: PASSED

Checked before this file was written, at HEAD `e14a213` with a clean tree:

- All nine files under `key-files.created` exist.
- Commits `5e3a26e`, `b6833e7` and `e14a213` exist; `git rev-list --count 662379e..HEAD` is 3.
- Plan verification re-run: `swift build` exit 0; `swift test` prints `Test run with 52 tests in 1 suite passed`; `ja11-probe` exits 0 and prints the slot with its name, the pre-gain, `filters: 5` and five filter lines; the `0xAA`, `0x4B|0x54` and `SeizeDevice` greps find nothing under `Sources`; `IOHIDDeviceSetReport(` call sites outside comments: 1.
- Every Task 1 and Task 2 acceptance criterion was run and passed.

---
*Phase: 01-device-link*
*Completed: 2026-10-10*
