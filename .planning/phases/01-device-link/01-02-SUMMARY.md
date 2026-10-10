---
phase: 01-device-link
plan: 02
subsystem: device-link
tags: [swift, swiftpm, iokit, hid, swift-testing, asyncstream, cli]

# Dependency graph
requires:
  - phase: 01-device-link plan 01
    provides: JA11Kit read path (FiioFrame, HIDTransport behind ReportTransport, JA11Device actor, EQ model) and the one-shot ja11-probe
provides:
  - FakeTransport and 31 device behaviour tests that run without the dongle
  - LinkUpdate and JA11Device.watch(), with a fresh read on every connect
  - ja11-probe --watch, --help, and exit statuses 0 to 4
  - --raw info lines for Input Monitoring status and reply header offset
  - Device evidence for the four D-16 questions
affects: [phase-2-write-path, phase-3-app-ui]

# Actuals (#2632)
actuals:
  tokens: 9020
  tasks: 3
  commits: 5
plan_head_before: 1f1bf2f62de213e4ffbb9b701c6ac52826a10570
plan_head_after: a0527e501c695bdf9328a4386043b450c653d545

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FakeTransport: an in-memory ReportTransport with a responder closure, for device tests without IOKit"
    - "watch(): the actor forwards each transport event to one internal stream; a single task turns them into LinkUpdate values and runs one read per connect"
    - "Connection epoch: a counter raised on every connect lets readState reject a read that spans a replug"
    - "Probe arguments are parsed before a transport exists; errors go to stderr, state to stdout"

key-files:
  created:
    - Tests/JA11KitTests/JA11DeviceTests.swift
    - Tests/JA11KitTests/HIDTransportErrorTests.swift
  modified:
    - Sources/JA11Kit/Device/JA11Device.swift
    - Sources/ja11-probe/main.swift

key-decisions:
  - "readState ends with disconnected when the dongle was replugged while the read was under way, so one state never combines values from two connections"
  - "watch() supports one watcher: a later call ends the earlier stream. When an open had already failed before watching began, the first update is that openFailed"
  - "The probe checks all arguments before acting, so an unknown argument exits 2 even when --help is also given"
  - "Input Monitoring status was unknown while open and reads succeeded, so no Input Monitoring grant was needed for the probe as launched here; the refusal path stays in place and unproven on the device"

patterns-established:
  - "Device logic is tested through FakeTransport; no test creates the real transport"
  - "Probe exit statuses: 0 state printed, 1 no JA11, 2 usage error, 3 access refused, 4 read failed"

requirements-completed: ["LINK-02", "LINK-03", "LINK-04", "LINK-05", "LINK-06"]

coverage:
  - id: D1
    description: "The link follows connect and disconnect: watch() reports each change in order and reads the state again on every connect, across repeated cycles"
    requirement: "LINK-02"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/JA11DeviceTests.swift#watchReadsOnConnectAndReadsAgainAfterAReplug, #watchFollowsThreeConnectAndDisconnectCyclesInOrder, #watchReportsAFailedReadAndStillFollowsTheNextConnect, #anUnplugDuringTheWatchersReadShowsAsDisconnectedOnly"
        status: pass
      - kind: e2e
        ref: "plan 01-02 Task 2 verify: ja11-probe --watch on the real dongle prints connected and the state, is alive after 5 s, exits 0 on SIGTERM"
        status: pass
    human_judgment: true
    rationale: "A real unplug and replug through the opened IOHIDManager has not been done. The tests use FakeTransport and the device run kept the dongle attached. Human check 1 below."
  - id: D2
    description: "Reads are truthful under failure: fixed request order, replies accepted only for the command and filter index asked for, count 0 and count above 5 handled without a filter request, timeouts as did-not-answer errors, unplug ends a waiting read, a second read is refused as busy"
    requirement: "LINK-03"
    verification:
      - kind: unit
        ref: "swift test: Test run with 83 tests in 3 suites passed (suite JA11DeviceTests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A probe run sends only GET frames for commands 0x15 to 0x18 and two runs print identical output"
    requirement: "LINK-04"
    verification:
      - kind: e2e
        ref: "plan 01-02 Task 3 verify: --raw run, awk check on every tx: line; two plain runs compared byte for byte"
        status: pass
      - kind: other
        ref: "source guards: no 0xAA, 0x4B, 0x54, SeizeDevice, process-starting call or prompt-requesting access call under Sources; one IOHIDDeviceSetReport( call site"
        status: pass
    human_judgment: false
  - id: D4
    description: "The dongle's volume and play/pause buttons keep working while ja11-probe --watch holds the device"
    requirement: "LINK-05"
    verification: []
    human_judgment: true
    rationale: "Needs physical button presses. Human check 3 below."
  - id: D5
    description: "A refused open is classified as access denied, worded with the Input Monitoring path, and ends the probe with status 3"
    requirement: "LINK-06"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/HIDTransportErrorTests.swift (5 tests); JA11DeviceTests#aRefusedOpenIsReportedAsTheTransportError, #watchPassesOnAFailedOpen"
        status: pass
    human_judgment: true
    rationale: "No refusal occurred on the device and one cannot be produced on demand. The exit status 3 path in main.swift has no automated test. Human check 4 below."
  - id: D6
    description: "ja11-probe has --help, rejects unknown arguments with status 2 before touching the device, and --raw prints the three info lines"
    verification:
      - kind: e2e
        ref: "plan 01-02 Task 1 and Task 3 verify commands (--bogus exits 2, --help lists --raw and --watch, info lines present)"
        status: pass
    human_judgment: false

# Metrics
duration: 6min
completed: 2026-10-10
status: complete
---

# Phase 1 Plan 02: Device Link behaviour, watch mode and device evidence Summary

**`ja11-probe --watch` backed by `JA11Device.watch()`, 31 device tests on a fake transport, distinct exit statuses, and a `--raw` run on the real JA11 showing GET-only traffic with identical repeated reads**

## Performance

- **Duration:** 6 min
- **Started:** 2026-10-10T13:22:32Z
- **Completed:** 2026-10-10T13:28:38Z
- **Tasks:** 3 of 3
- **Files:** 2 created, 2 modified

## Accomplishments

- Every behaviour in the plan's Task 1 and Task 2 lists has a passing test that runs without the dongle (83 tests in 3 suites).
- `ja11-probe --watch` reads the real dongle on connect, keeps running, and exits 0 on SIGTERM and on SIGINT.
- On the real dongle a `--raw` run sent GET frames only, and two plain runs printed identical output.
- Not done, and not claimed: a physical unplug and replug, a run with no dongle, the button check and the permission check. They are listed under Pending human verification.

## Device evidence

One complete `ja11-probe --raw` run on the real JA11 (exit status 0):

```text
info: input-monitoring access: unknown
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
info: reply header offset: 1
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
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
info: request frame form: padded
```

### (a) GET replies

All four commands were answered, each by the report that followed its request:

| Command | `tx:` | `rx:` |
|---|---|---|
| 0x16 preset slot | `bb 0b 00 00 16 00 00 ee` + 12 zero bytes | `02 bb 0b 00 00 16 01 03 bd ee ...` (slot 3) |
| 0x18 filter count | `bb 0b 00 00 18 00 00 ee` + 12 zero bytes | `02 bb 0b 00 00 18 01 05 94 ee ...` (5 filters) |
| 0x17 pre-gain | `bb 0b 00 00 17 00 00 ee` + 12 zero bytes | `02 bb 0b 00 00 17 02 00 00 f1 ee ...` (0.0 dB) |
| 0x15 filter, index 0 to 4 | `bb 0b 00 00 15 01 NN 00 ee` + 11 zero bytes | `02 bb 0b 00 00 15 08 NN ...`, one per index, index byte matching |

### (b) Frame form (D-03)

`info: request frame form: padded`. The JA11 answered the padded 20-byte form on the first request, so there is one `tx:` line per request and the unpadded form was never sent in this plan's runs. Whether the JA11 would also answer the unpadded form is still not known.

### (c) Input Monitoring

- `info: input-monitoring access: unknown` (from `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`; neither granted nor denied).
- The open succeeded and all eight reads were answered.
- Where it ran: started by the Claude Code Bash tool with its default sandbox setting; the sandbox-off option was not used. No environment variable inside the process confirmed or ruled out a sandbox, so "inside the tool sandbox" is the launch setting, not something observed from inside.
- Conclusion, by the plan's rule: status `unknown` together with a successful read means macOS did not require an Input Monitoring grant for this device, for a process launched this way. No refusal was seen in any run of plan 01-01 or 01-02.
- Still open: whether the same holds for a double-clicked `.app` (Phase 4) and for a process whose launching app has been switched off under Input Monitoring. Human check 4 covers the second.

### (d) Report layout

`info: reply header offset: 1`. Each input report is **21 bytes**: the report-ID byte `02`, then the 20-byte payload starting `bb 0b`.

### What this means for Phase 2

- **LINK-03, WRITE-02 (read-back after Apply) and APP-09 can rely on reads.** The JA11 answers all four GET commands in the padded form, and three reads in this plan plus three in plan 01-01 returned the same values.
- **Limits of that statement.** Every gain on the dongle is still 0.0 dB, pre-gain included, so the sign and the ×10 scale of gains are proven by unit tests only. Only the active slot (USER1) was read; reading a factory preset's filters by selecting its slot (the WRITE-04 assumption) needs a slot switch, which is a write, and was not tried.
- **The byte before `ee` in a reply still varies** (`bd`, `94`, `f1`, `7f`, `6e`, `30`, `b5`, `e5`, the same values as in plan 01-01 for the same content). It looks like a checksum of the reply; that was not verified. Phase 2 should settle it before sending the first SET frame.
- **LINK-06.** No permission was needed here, so the app should not tell the user to grant Input Monitoring up front. The message naming System Settings → Privacy & Security → Input Monitoring should stay for the case where the open is refused with a not-permitted or not-privileged result; that case has unit tests but was never seen on the device.

## Pending human verification

`human_verify_mode` is `end-of-phase`. None of these four was done or simulated in this run. The binary is at `"$(swift build --show-bin-path)/ja11-probe"` (run from the repo root).

1. **Unplug and replug (LINK-02, D-09).** Run `ja11-probe --watch`. Unplug the JA11, wait about 3 seconds, plug it back in. Do this twice.
   Expected: each unplug prints `disconnected` within about 2 seconds; each plug-in prints `connected` followed by `slot:`, `pre-gain:` and `filters:` lines; the probe is never restarted.
   Why it matters: this is the first exercise of the replug path through the opened IOHIDManager on real hardware.
2. **No dongle (D-13).** Unplug the JA11, run `ja11-probe` with no arguments, then plug the dongle back in.
   Expected: within about 3 seconds it prints `No JA11 found (looked for USB VID 0x2972, PID 0x0102). Plug the dongle in and run again.` and exits with status 1 (`echo $?`).
3. **Buttons (LINK-05, D-08).** With `ja11-probe --watch` running, press volume up and volume down on the dongle, then play/pause while music is playing on the Mac.
   Expected: the Mac's volume indicator moves and playback pauses and resumes, exactly as when the probe is not running.
4. **Permission (LINK-06, D-10).** Open System Settings → Privacy & Security → Input Monitoring. Recall whether macOS ever showed a permission prompt while the probe ran. If the app that runs the probe (the terminal, or Claude) has an entry there that is switched on, switch it off, run `ja11-probe`, then switch it back on (the app may need reopening).
   Expected: if macOS requires the permission, with the entry off the probe prints a message naming Input Monitoring and that settings path and exits with status 3, and with it back on it reads the state again. If there is no entry and no prompt ever appeared, or the probe still reads with the entry off, macOS does not require the permission, which matches (c) above.

**Requirement status.** `requirements-completed` in the frontmatter repeats the plan's list, as the template requires. In `REQUIREMENTS.md` only LINK-03 and LINK-04 were marked complete after this plan. LINK-02, LINK-05 and LINK-06 were left pending on purpose: each depends on one of the checks above.

## Task Commits

1. **Task 1, tests** - `b89bc9d` (test)
2. **Task 1, probe usage and exit statuses** - `2d23f2a` (feat)
3. **Task 2, RED** - `7e76674` (test)
4. **Task 2, GREEN** - `584c8d1` (feat)
5. **Task 3, `--raw` info lines and trace test** - `a0527e5` (feat)

**Plan metadata:** the docs commits that follow this file.

## TDD

- **Task 1: the tests did not fail first.** All 22 new tests (17 device, 5 error mapping) passed against the sources as plan 01-01 left them. The plan expected this could happen ("this task proves them and closes any gap it finds"); the behaviours were built in 01-01. No source in `JA11Kit` was changed for Task 1 and no test was loosened. The tests were not mutation-checked, so their ability to catch a regression is argued from reading them, not demonstrated.
- **Task 2 RED:** 8 tests added with `LinkUpdate` and a stub `watch()` that returns a finished stream, so failures are assertion failures. Result: 82 tests, 75 passed, 7 failed (all seven watch tests, for example `watchPassesOnAFailedOpen`: expected `[.openFailed(refusal)]`, got nothing). `gsd-tools check tdd-red-evidence` returned `RED_EVIDENCE_OK` (`target_test_failed`), matched at suite level as in plan 01-01.
- The eighth test, `aReplugInTheMiddleOfAReadEndsThatRead`, passed in the RED run. Before the fix its outcome depended on task scheduling; it was never seen failing. It guards the connection-epoch check (deviation 1).
- **Task 2 GREEN:** `watch()` and the probe's watch mode; 82 of 82 pass.
- **Task 3** is not a TDD task; its trace test passed on first run because the trace was built in 01-01.

## Files Created/Modified

- `Tests/JA11KitTests/JA11DeviceTests.swift` (new) - `FakeTransport`, `Recorder`, reply vectors, 26 device tests
- `Tests/JA11KitTests/HIDTransportErrorTests.swift` (new) - 5 tests for open-result classification and messages
- `Sources/JA11Kit/Device/JA11Device.swift` - `LinkUpdate`, `watch()`, connection epoch in `readState()`
- `Sources/ja11-probe/main.swift` - argument parsing, usage text, exit statuses, watch mode, signal handling, `--raw` info lines
- `Sources/JA11Kit/HID/HIDTransport.swift` - not changed; nothing showed a defect in it

## Decisions Made

- **One state, one connection.** See deviation 1.
- **`watch()` reports an earlier failed open.** "The link as it is" at the start of watching is `.connected` plus a read when connected, and `.openFailed` when the last thing the transport reported was a failed open. The plan names only the first case.
- **All arguments are checked before any acts.** `ja11-probe --help --bogus` exits 2.
- **Signal sources are created in a nonisolated function.** The first version set the handler from top-level code; the handler was then inferred main-actor-isolated, ran on a global queue, and Swift printed a data-race warning at SIGTERM. Fixed before the Task 2 commit and the device check was re-run.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] A read that spans a replug is rejected**
- **Found during:** Task 2, designing `watch()`
- **Issue:** `readState()` makes several requests. If the dongle went away and came back between two of them, the later requests would succeed and the returned state would combine values read over two connections. The plan's second prohibition forbids presenting anything but a freshly read state after a reconnect.
- **Fix:** a counter raised on every connect; `readState()` throws `.disconnected` when it changed during the read. In watch mode the read for the new connect then supplies the state.
- **Files modified:** `Sources/JA11Kit/Device/JA11Device.swift`, `Tests/JA11KitTests/JA11DeviceTests.swift`
- **Verification:** `aReplugInTheMiddleOfAReadEndsThatRead` (see the TDD note on what it does and does not show)
- **Committed in:** `7e76674` (test), `584c8d1` (fix)

**2. [Process] Task 1 has no failing-first run** - see TDD above.

**3. [Process] RED commit carries a stub** - `LinkUpdate` and a stub `watch()` are in the `test` commit so the tests compile, as in plan 01-01.

**4. [Scope note] Tests beyond the plan's list:** `watchStartsTheTransportItself` (the plan says `watch()` calls `start()` itself) and the replug test above.

---

**Total deviations:** 1 auto-fixed (missing critical), 2 process notes, 1 scope note
**Impact on plan:** The fix narrows what a read may return. No change to what is sent. `isGetRequest` and the `readFilter(index:)` trap from plan 01-01 are unchanged.

## Issues Encountered

- The harness blocks a foreground `sleep`, so the plan's watch check was run as a background command, unchanged apart from two added `echo` lines.
- `check tdd-red-evidence` needs a JSON record with `command`, `exitCode`, `targetTest`, `expected`, `actual` and the runner output in `output`; the xUnit file alone is rejected.

## What was sent to the dongle

Six probe runs, 48 frames, every one a padded GET request built by `FiioFrame.getRequest` and passed through the transport's send gate: three `--watch` runs (one read each on connect), one `--raw` run, two plain runs. Commands 0x16, 0x18, 0x17 and 0x15 only, on report 0x02. The `tx:` lines of the `--raw` run are above; the other five runs were not traced, and what they sent is known from the code path, not from a capture. No other tool or frame was used.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 1's automated work is complete. The four human checks above remain for end-of-phase verification; check 1 is the one that could still uncover a defect (in `HIDTransport`'s replug path).
- For Phase 2: reads are reliable in the padded form; the send gate must be replaced deliberately; the varying byte before `ee` and the gain sign and scale are still to be confirmed on the device.
- No blockers.

## Self-Check: PASSED

Checked at HEAD `a0527e5` with a clean tree, before this file was written:

- Both created files exist; commits `b89bc9d`, `2d23f2a`, `7e76674`, `584c8d1`, `a0527e5` exist; `git rev-list --count 1f1bf2f..HEAD` is 5.
- `swift build` exit 0; `swift test` prints `Test run with 83 tests in 3 suites passed`.
- Task 1: `--bogus` exits 2 with `unknown argument` on stderr and nothing on stdout; `--help` exits 0; the five grep criteria pass.
- Task 2: watch check passed (alive after 5 s, exit 0 on SIGTERM, `connected` and `slot:` printed); `--help` lists `--watch`; one `IOHIDManagerCreate(` call site.
- Task 3: `--raw` check, two-run comparison and all source guards passed.
- The four human checks were not run.

---
*Phase: 01-device-link*
*Completed: 2026-10-10*
