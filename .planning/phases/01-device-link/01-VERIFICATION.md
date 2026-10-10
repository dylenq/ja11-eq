---
phase: 01-device-link
verified: 2026-10-10T13:32:47Z
status: human_needed
score: 12/16 must-haves verified
covered_files:
  - .gitignore
  - .planning/phases/01-device-link/01-01-PLAN.md
  - .planning/phases/01-device-link/01-01-SUMMARY.md
  - .planning/phases/01-device-link/01-02-PLAN.md
  - .planning/phases/01-device-link/01-02-SUMMARY.md
  - Package.swift
  - Sources/JA11Kit/Device/JA11Device.swift
  - Sources/JA11Kit/HID/HIDTransport.swift
  - Sources/JA11Kit/Model/EQModel.swift
  - Sources/JA11Kit/Protocol/FiioFrame.swift
  - Sources/JA11Kit/Protocol/JA11Commands.swift
  - Sources/ja11-probe/main.swift
  - Tests/JA11KitTests/FiioFrameTests.swift
  - Tests/JA11KitTests/HIDTransportErrorTests.swift
  - Tests/JA11KitTests/JA11DeviceTests.swift
covered_digest: "v2:sha256:7ca3a82a3c4b8050353162f23a74237ad348451e5c7af167d23a96378d12580d"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Unplug and replug (LINK-02, SC 3). From the repo root run `swift build`, then `\"$(swift build --show-bin-path)/ja11-probe\" --watch`. Unplug the JA11, wait about 3 seconds, plug it back in. Do this twice. Stop with Ctrl-C."
    expected: "Each unplug prints `disconnected` within about 2 seconds. Each plug-in prints `connected` followed by `slot:`, `pre-gain:`, `filters:` and five `filter N:` lines. The probe is never restarted, and Ctrl-C ends it with status 0."
    why_human: "The dongle has to be physically unplugged. The follow-the-link logic passes its tests on a fake transport, but the IOKit removal and re-match callbacks have never run on the real device."
  - test: "No dongle (D-13). Unplug the JA11, run `\"$(swift build --show-bin-path)/ja11-probe\"; echo $?`, then plug the dongle back in."
    expected: "Within about 3 seconds it prints `No JA11 found (looked for USB VID 0x2972, PID 0x0102). Plug the dongle in and run again.` and the status shown is 1."
    why_human: "The dongle has to be physically absent."
  - test: "Buttons (LINK-05, SC 4). With `ja11-probe --watch` running, press volume up and volume down on the dongle, then play/pause while music is playing on the Mac."
    expected: "The Mac's volume indicator moves up and down and playback pauses and resumes, exactly as when the probe is not running."
    why_human: "Needs physical button presses and a look at how the Mac reacts. The code opens the device non-exclusively at every open call, which is necessary but does not prove the buttons still arrive."
  - test: "Permission refusal (LINK-06, SC 5). Open System Settings → Privacy & Security → Input Monitoring. If the app that runs the probe (the terminal, or Claude) has an entry that is switched on, switch it off, run `ja11-probe; echo $?`, then switch it back on (the app may need reopening)."
    expected: "If macOS requires the permission: with the entry off the probe prints a message naming Input Monitoring and the path System Settings → Privacy & Security → Input Monitoring and the status is 3; with it back on it reads the state again. If there is no entry, or the probe still reads with the entry off: macOS does not require the permission for this device, which matches the `input-monitoring access: unknown` evidence, and the refusal message stays proven by unit tests only."
    why_human: "Only the user can change a privacy setting and see a macOS prompt. No refusal has ever been produced on this Mac."
  - test: "Review four flagged prohibitions (see Prohibitions table): one test-tier item with no test behind it (only the JA11 is matched) and three judgment-tier items (no invented values, no circumventing a refusal, only fresh state after reconnect)."
    expected: "You agree with the verifier's reading that each holds, or you ask for a test or change."
    why_human: "Judgment-tier prohibitions need an explicit human decision; a test-tier prohibition without a test is never passed silently."
---

# Phase 1: Device Link Verification Report

**Phase Goal:** The Mac finds the JA11 on its own, stays linked across unplug and replug, and reads the DAC's real EQ state — without changing anything on the device.
**Verified:** 2026-10-10T13:32:47Z
**Status:** human_needed
**Re-verification:** No — initial verification

No gaps were found. Everything that can be checked without touching the dongle by hand was checked on the real device and holds. Four truths depend on physical checks that have not been done, so the phase cannot be marked passed yet.

## Goal Achievement

### Observable Truths

Truths 1–5 are the roadmap success criteria; 6–16 come from the two plans (duplicates of 1–5 merged).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `ja11-probe` with no arguments finds the dongle and prints slot, pre-gain and every filter as read from the device (SC 1) | ✓ VERIFIED | Run by the verifier on the real JA11: exit 0, `slot: 3 (USER1)`, `pre-gain: +0.0 dB`, `filters: 5`, five `filter N:` lines with type, Hz, dB and Q. Values decode correctly from the raw `rx:` bytes (e.g. `00 3b 00 46 01` → 59 Hz, Q 0.70, low-shelf). Matching uses VID `0x2972` and PID `0x0102` only (`HIDTransport.swift:103-107`). |
| 2 | Running the probe changes nothing: only GET (`BB 0B`) frames, two runs identical, active preset unchanged (SC 2) | ✓ VERIFIED | Run 1 and run 2 output byte-identical (`diff` clean), slot 3 before and after. A `--raw` run between them shows 8 `tx:` lines, all matching the four GET frames for `0x16`, `0x18`, `0x17`, `0x15`. `send()` refuses anything `FiioFrame.isGetRequest` rejects, there is one `IOHIDDeviceSetReport` call site, and no SET encoder exists in `Sources/`. |
| 3 | With the probe left running, unplug is reported as disconnected and replug as connected with the state read again (SC 3, LINK-02) | ? HUMAN NEEDED | Logic verified: `watchReadsOnConnectAndReadsAgainAfterAReplug` and `watchFollowsThreeConnectAndDisconnectCyclesInOrder` pass. Verifier ran `--watch` for about 6 s: stayed alive, printed `connected` plus the state, exited 0 on SIGTERM. The physical unplug/replug has not been done. |
| 4 | While the probe has the device open, the volume and play/pause buttons still control the Mac (SC 4, LINK-05) | ? HUMAN NEEDED | All three open calls use `kIOHIDOptionsTypeNone` (`HIDTransport.swift:91,133,162`); no `Seize` anywhere in `Sources/`. Button behaviour itself not observed. |
| 5 | If macOS refuses access, the probe names Input Monitoring and where to grant it, exit status 3; other open errors show their IOKit code (SC 5, LINK-06) | ? HUMAN NEEDED | Mapping and message verified by `HIDTransportErrorTests` (5 tests pass); `aRefusedOpenIsReportedAsTheTransportError` passes; `main.swift` maps `.transport(.accessDenied)` to status 3 in both modes. A real refusal has never been produced: this Mac reports `input-monitoring access: unknown` and opens the device without a grant. |
| 6 | `swift test` passes without the device; GET frames equal the D-03 reference frames in both forms; replies decode per D-05, including `FF C4` → −6.0 dB | ✓ VERIFIED | `swift test`: 83 tests in 3 suites passed. No test creates an `HIDTransport` or calls IOKit. Reference frames are literal byte arrays in `FiioFrameTests.swift`. |
| 7 | A reply decodes the same with its header at offset 0 or 1 (D-06) | ✓ VERIFIED | `everyReplyDecodesTheSameBehindALeadingReportIDByte`, `repliesWithALeadingReportIDByteGiveTheSameState` pass. Real device delivers offset 1 (`info: reply header offset: 1`) and decodes correctly. |
| 8 | First request goes out padded; only if unanswered is it sent once unpadded; the answered form is kept (D-03) | ✓ VERIFIED | `fallsBackToTheUnpaddedFormOnceAndKeepsIt`, `aMissingPreGainReplyIsADidNotAnswerErrorWithoutAFallbackFrame` pass. Real device: `info: request frame form: padded`, one `tx:` per request. |
| 9 | Empty, headerless or too-short reports are rejected and yield no value | ✓ VERIFIED | `emptyReportGivesNoFrame`, `allZeroReportGivesNoFrame`, `headerAtAnyOtherOffsetGivesNoFrame`, `preGainIsNilWhenTheReplyIsCutToSevenBytes`, `bandIsNilWhenTheReplyIsCutToThirteenBytes` pass. |
| 10 | `--raw` additionally prints every frame sent and received as hex, the frame form, the Input Monitoring status and the reply header offset (D-15) | ✓ VERIFIED | Observed in the verifier's own `--raw` run: 8 `tx:`, 8 `rx:`, and the three `info:` lines. |
| 11 | No JA11 attached: the one-shot probe says so and exits 1; a device answering neither form gives a did-not-answer error in about 2 s and exit 4 | ? HUMAN NEEDED | Logic verified: `noDongleWithinTheDiscoveryTimeoutIsNotFound`, `aDeviceThatAnswersNeitherFormIsReportedAfterTwoSends` pass; defaults are 2 s discovery and 1 s per reply; `exitStatus(for:)` maps to 1 and 4. The real run with no dongle has not been done. |
| 12 | An unplug during a waiting read ends it at once as disconnected; a second read while one waits is refused as busy | ✓ VERIFIED | `anUnplugEndsAWaitingReadAtOnce`, `aSecondReadWhileOneIsWaitingIsRefusedAsBusy`, `aReplugInTheMiddleOfAReadEndsThatRead` pass. |
| 13 | Identical filters stay separate entries; a reply is accepted only for the command and filter index asked for | ✓ VERIFIED | `twoIdenticalFiltersStayTwoEntriesUnderTheirOwnIndexes`, `aStaleReplyForAnotherCommandIsNotTakenAsTheAnswer`, `aFilterReplyWithAnotherIndexIsNotTakenAsTheAnswer` pass. |
| 14 | Count 0 gives an empty list with no filter request; a count above 5 is an error naming the value | ✓ VERIFIED | `aCountOfZeroGivesNoFiltersAndSendsNoFilterRequest`, `aCountAboveFiveIsAnErrorNamingTheValueAndSendsNoFilterRequest` pass. |
| 15 | Filters are returned in ascending index order on every run | ✓ VERIFIED | `filtersComeBackInAscendingIndexOrder` passes; real output is 0–4 in both runs. |
| 16 | The plan summary records the D-16 device evidence | ✓ VERIFIED | `01-02-SUMMARY.md` § Device evidence. The verifier's independent `--raw` run reproduced it byte for byte: GET answered, padded form, access `unknown`, header offset 1. |

**Score:** 12/16 truths verified (0 present, behavior-unverified; 4 awaiting human checks at the dongle)

### Prohibitions

| # | Must NOT | Tier | Status | Evidence |
|---|----------|------|--------|----------|
| P1 | Send anything except the four GET requests on report `0x02` | test | ✓ VERIFIED | 12 `gateRejects…` tests plus `theOnlyCommandsAreTheFourReadCommands` pass; `send()` gates on `isGetRequest` before its only `IOHIDDeviceSetReport`; no `0xAA`, `0x4B`, `0x54` literal in `Sources/`; the CLI accepts flags only. |
| P2 | Open or listen to any HID device other than VID `0x2972` / PID `0x0102` | test | ⚠️ FLAGGED (unverified-prohibition) | No test enforces it. By reading: one `IOHIDManagerSetDeviceMatching` call with both keys, and reports with any other report ID are dropped. Human review recommended. |
| P3 | Present a value the device did not send as the DAC's state | judgment | ⚠️ FLAGGED (verifier's reading: holds) | `readState()` is all-or-nothing with a connection-epoch check; no defaults in the decode path; `aQOfZeroIsNotReplacedByADefault` and unknown slot/type tests pass. |
| P4 | Get around a macOS access refusal | judgment | ⚠️ FLAGGED (verifier's reading: holds) | No `tccutil`, `Process(`, `posix_spawn` or `IOHIDRequestAccess` in `Sources/`; only the status query `IOHIDCheckAccess`. |
| P5 | After a reconnect, show anything but a freshly read state | judgment | ⚠️ FLAGGED (verifier's reading: holds) | `watchReadsOnConnectAndReadsAgainAfterAReplug` shows a different state after replug; `anUnplugDuringTheWatchersReadShowsAsDisconnectedOnly` passes. |

### Required Artifacts

`verify.artifacts` reported 8/8 (plan 01-01) and 5/5 (plan 01-02) passing. All were also read in full.

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Package.swift` | Library, executable, test target, macOS 14, no dependencies | ✓ VERIFIED | 16 lines, three targets, no dependencies |
| `Sources/JA11Kit/Protocol/JA11Commands.swift` | IDs, slots, limits | ✓ VERIFIED | Only four commands, all reads |
| `Sources/JA11Kit/Protocol/FiioFrame.swift` | GET building, reply parsing, send gate | ✓ VERIFIED | 141 lines, used by device, transport and CLI |
| `Sources/JA11Kit/HID/HIDTransport.swift` | IOHIDManager wrapper | ✓ VERIFIED | 182 lines; drives the real dongle |
| `Sources/JA11Kit/Device/JA11Device.swift` | Async read API and `watch()` | ✓ VERIFIED | 401 lines; no write operation |
| `Sources/JA11Kit/Model/EQModel.swift` | Model types and report lines | ✓ VERIFIED | 108 lines |
| `Sources/ja11-probe/main.swift` | CLI with `--watch`, `--raw`, `--help`, exit statuses | ✓ VERIFIED | `--bogus` → status 2, `--help` → status 0, both without opening the device |
| `Tests/JA11KitTests/*.swift` (3 files) | Codec, device and error tests | ✓ VERIFIED | 999 lines, 83 tests, real assertions on a fake transport |
| `01-02-SUMMARY.md` § Device evidence | D-16 answers | ✓ VERIFIED | Reproduced independently |

### Key Link Verification

`verify.key-links` reported 5/5 (plan 01-01) and 4/4 (plan 01-02) verified; confirmed by reading.

| From | To | Via | Status |
|------|----|-----|--------|
| `main.swift` | `JA11Device` | `readState()` one-shot, `watch()` loop | WIRED |
| `JA11Device` | `FiioFrame` | `getRequest` for every request, `replyFrame` for every report | WIRED |
| `JA11Device` | transport | `ReportTransport` protocol only; `ConnectionEvent` drives the link | WIRED |
| `HIDTransport.send` | `FiioFrame.isGetRequest` | guard is the first statement | WIRED |
| `HIDTransport` | `JA11` constants | matching and report ID | WIRED |
| `JA11DeviceTests` | `ReportTransport` | `FakeTransport` conformance | WIRED |
| `main.swift` | `FiioFrame.hex` / `replyFrame` | `--raw` trace | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| `ja11-probe` output | `EQState` | Input reports from the JA11, decoded by `FiioReplyFrame` | Yes — printed values match the `rx:` bytes of the same run | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Package builds | `swift build` | Build complete | ✓ PASS |
| Tests pass | `swift test` (once) | 83 tests in 3 suites passed | ✓ PASS |
| One-shot read | `ja11-probe` | exit 0, slot 3, 5 filters | ✓ PASS |
| Read-only and repeatable | two runs with a `--raw` run between, `diff` | identical; 8 `tx:` lines, all GET | ✓ PASS |
| Watch stays up and stops cleanly | background `--watch --raw`, SIGTERM after about 6 s | alive, `connected` plus state, 8 GET frames, exit 0 | ✓ PASS |
| Usage handling | `--bogus`, `--help` | status 2 and 0 | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exists and neither plan declares one. Not applicable. (`ja11-probe` is the deliverable, covered above.)

### Requirements Coverage

All six phase requirement IDs appear in the plans' frontmatter (01-01: LINK-01, 03, 04, 05, 06; 01-02: LINK-02, 03, 04, 05, 06). No orphaned requirements.

| Requirement | Plan | Description | Status | Evidence |
|-------------|------|-------------|--------|----------|
| LINK-01 | 01-01 | JA11 found automatically | ✓ SATISFIED | Truth 1 |
| LINK-02 | 01-02 | Status follows unplug and replug | ? NEEDS HUMAN | Truth 3 |
| LINK-03 | 01-01, 01-02 | Slot, pre-gain and filters can be read | ✓ SATISFIED | Truths 1, 6, 7, 13–15 |
| LINK-04 | 01-01, 01-02 | `ja11-probe` prints state without changing anything | ✓ SATISFIED | Truth 2, P1 |
| LINK-05 | 01-01, 01-02 | Buttons keep working while open | ? NEEDS HUMAN | Truth 4 |
| LINK-06 | 01-01, 01-02 | User told which permission to grant and where | ? NEEDS HUMAN | Truth 5 |

`REQUIREMENTS.md` already shows LINK-02, LINK-05 and LINK-06 as pending, which is correct until the human checks are done. The two SUMMARY files list them under `requirements-completed`; that claim is not accepted here.

### Anti-Patterns Found

None. No `TBD`, `FIXME`, `XXX`, `TODO`, `HACK` or placeholder text in `Sources/`, `Tests/` or `Package.swift`; no stubs or empty implementations.

Notes, not gaps:

| Item | Severity | Note |
|------|----------|------|
| Every gain on the dongle is 0.0 dB | ℹ️ Info | The sign and ×10 scale of gains are proven by unit tests only, not by device data. Matters for Phase 2 read-back. |
| Byte before `ee` in replies varies (`bd`, `94`, `f1`, …) | ℹ️ Info | Probably a checksum; the parser ignores it. Phase 2 should settle it before the first SET frame. |
| `IOHIDManagerOpen` result is discarded (`HIDTransport.swift:133`) | ℹ️ Info | Deliberate and commented; the per-device open classifies the result. Whether a refusal surfaces through that path is exactly human check 4. |

### Human Verification Required

Binary: from `/Users/dylenquyn/Documents/JA11` run `swift build`, then `"$(swift build --show-bin-path)/ja11-probe"`.

#### 1. Unplug and replug (LINK-02, SC 3)

**Test:** Run `ja11-probe --watch`. Unplug the JA11, wait about 3 seconds, plug it back in. Do this twice. Stop with Ctrl-C.
**Expected:** Each unplug prints `disconnected` within about 2 seconds. Each plug-in prints `connected` followed by `slot:`, `pre-gain:`, `filters:` and the filter lines. The probe is never restarted.
**Why human:** The dongle has to be physically unplugged; the IOKit removal and re-match path has never run on the real device.

#### 2. No dongle (D-13)

**Test:** Unplug the JA11, run `ja11-probe; echo $?`, then plug it back in.
**Expected:** Within about 3 seconds: `No JA11 found (looked for USB VID 0x2972, PID 0x0102). Plug the dongle in and run again.` and status 1.
**Why human:** The dongle has to be physically absent.

#### 3. Buttons (LINK-05, SC 4)

**Test:** With `ja11-probe --watch` running, press volume up and down on the dongle, then play/pause while music plays on the Mac.
**Expected:** The volume indicator moves and playback pauses and resumes, exactly as when the probe is not running.
**Why human:** Needs physical button presses and a look at the Mac's reaction.

#### 4. Permission refusal (LINK-06, SC 5)

**Test:** In System Settings → Privacy & Security → Input Monitoring, if the app that runs the probe has an entry that is on, switch it off, run `ja11-probe; echo $?`, then switch it back on.
**Expected:** If macOS requires the permission: a message naming Input Monitoring and that settings path, status 3; with the entry back on, the state is read again. If there is no entry or the probe still reads: macOS does not require the permission here, and the refusal message remains proven by unit tests only.
**Why human:** Only the user can change a privacy setting and see a macOS prompt.

#### 5. Flagged prohibitions

**Test:** Read the Prohibitions table, rows P2–P5.
**Expected:** You accept the verifier's reading that each holds, or ask for a test (P2 has none) or a change.
**Why human:** Judgment-tier prohibitions need an explicit decision; a test-tier prohibition without a test is never passed silently.

### Gaps Summary

No gaps. The read path is real and works on the hardware: the probe finds the JA11 by itself, reads slot, pre-gain and five filters, sends only GET frames, and gives identical output on repeated runs. What remains is confirmation at the dongle of unplug/replug, the no-dongle exit, the buttons and the permission refusal, plus a decision on four flagged prohibitions.

---

_Verified: 2026-10-10T13:32:47Z_
_Verifier: Claude (gsd-verifier)_
