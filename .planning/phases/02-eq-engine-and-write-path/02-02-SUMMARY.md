---
phase: 02-eq-engine-and-write-path
plan: 02
subsystem: write-path
tags: [swift, swiftpm, hid, swift-testing, codable, backup, hard-link, actor]

# Dependency graph
requires:
  - phase: 02-eq-engine-and-write-path
    provides: "Plan 02-01: SET frame builders behind the send gate, EQCurve with clamped() and deviceState(), EQState.differences(from:), JA11Device.apply(_:) for the uninterrupted case, FakeDongle"
provides:
  - JA11Device.apply(_:) with interruption, drop-off-USB and busy handling (internal)
  - JA11Device.selectSlot(_:) and JA11Device.captureUser1() (internal)
  - DeviceBackup, BackupError, BackupStore with a never-overwrite saveIfAbsent
  - JA11Writer, the one public way to write (backup, apply, applyTestCurve, restore, selectSlot), with BackupOutcome, SlotReport, RestoreReport
  - EQCurve.testCurve(basedOn:)
  - FakeDongle with per-slot contents and switches for drops, silence and mismatches; FakeTransport.sendError
affects: [02-03 ja11-eq command, 02-04 first contact with writes, phase-3-app-ui, phase-4-readme-restore]

# Actuals (#2632)
actuals:
  tokens: 20378
  tasks: 2
  commits: 3
plan_head_before: 18530f46475faf27cc8301d62cfeeabfe996676d
plan_head_after: 50a39d516d234e36ca8e624627fa6bd25071a7d1

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One write operation at a time on the actor: apply, selectSlot and captureUser1 share a flag and refuse a second one as busy before sending anything"
    - "Before the save nothing is forgiven; after the save only the select frame may repeat"
    - "Backup file: full write to a temporary file in the same directory, then link(2) to the final name; no function replaces, changes or deletes an existing file"
    - "JA11Writer in front of the actor: every write operation calls backup() first"
    - "Tests that touch a file run in a fresh directory under the temporary directory and remove it"

key-files:
  created:
    - Sources/JA11Kit/Backup/BackupStore.swift
    - Sources/JA11Kit/Device/JA11Writer.swift
    - Tests/JA11KitTests/BackupStoreTests.swift
    - Tests/JA11KitTests/JA11WriterTests.swift
  modified:
    - Sources/JA11Kit/Device/JA11Device.swift
    - Sources/JA11Kit/Model/EQCurve.swift
    - Tests/JA11KitTests/FakeDongle.swift
    - Tests/JA11KitTests/ApplyTests.swift
    - Tests/JA11KitTests/JA11DeviceTests.swift

key-decisions:
  - "Pauses and timeouts: framePause 100 ms, saveSettle 1500 ms, reconnectTimeout 10 s, read-back retry wait 200 ms (new init parameter readBackRetryWait), link poll 10 ms while waiting for the dongle to come back"
  - "After a save these errors mean not usable yet and lead to another round: disconnected, notConnected, noReply, busy, transport(notConnected), transport(sendFailed); any other error ends the apply with that error"
  - "captureUser1() re-selects the slot that was active and requires the read-back to match, which goes beyond the letter of D-13: taking a backup leaves the device as it was found"
  - "An apply that cannot read the active slot at its start, for any reason including busy, ends with writeInterrupted and has sent nothing"
  - "The backup's savedAt is cut to whole seconds, which is what the ISO 8601 text in the file holds, so the backup returned equals the backup loaded"
  - "load() checks formatVersion on its own before decoding the rest, so a later format is reported as a version mismatch"
  - "A restore whose apply is not confirmed sends nothing further and leaves USER1 active"

patterns-established:
  - "Write-door tests record, per write frame the dongle receives, whether the backup file exists by then"
  - "FakeDongle models slots as the device does: select loads a slot's saved contents into the working state, a save stores the working state"

requirements-completed: ["WRITE-01", "WRITE-02", "WRITE-04", "WRITE-06", "WRITE-07", "WRITE-08"]

coverage:
  - id: D1
    description: "An apply survives a drop off USB after the save: it waits for the dongle, selects USER1, reads and is confirmed, without sending a value or save frame twice"
    requirement: "WRITE-07"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#applySurvivesADropOffUSBAfterTheSaveAndIsConfirmed"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#applyIsConfirmedWhileAWatcherReadsTheDeviceAfterTheReconnect"
        status: pass
    human_judgment: false
  - id: D2
    description: "A dongle that never returns or stays silent after the save ends the apply with noReadBack after the reconnect timeout; a read-back that differs is a mismatch with one line per value"
    requirement: "WRITE-02"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aDongleThatNeverComesBackEndsTheApplyWithNoReadBackAfterTheTimeout"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aDongleThatStaysSilentAfterTheSaveEndsTheApplyWithNoReadBack"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aGainStoredOneTenthOffIsReportedAsExactlyOneDifference"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aDongleThatReportsAnotherSlotAfterTheSaveIsAMismatch"
        status: pass
    human_judgment: false
  - id: D3
    description: "A disconnect, a replug or a send error before the save ends the apply with writeInterrupted; no save is sent and nothing is sent afterwards"
    requirement: "WRITE-07"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aDisconnectAfterTheThirdFilterEndsTheApplyWithoutASave"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aReplugBetweenTwoFiltersEndsTheApplyWithoutASave"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aSendErrorOnTheFourthSendEndsTheApplyWithoutASave"
        status: pass
    human_judgment: false
  - id: D4
    description: "No value frame is sent while another slot is active: the leading select is sent at most once and a failed or unconfirmed switch ends the apply and the restore without a value or save"
    requirement: "WRITE-04"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aDisconnectBetweenTheLeadingSelectAndItsReadBackEndsTheApplyWithoutAnyValue"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#restoreOnADongleThatDoesNotSwitchToUser1WritesNoValue"
        status: pass
    human_judgment: false
  - id: D5
    description: "A second write operation during an apply is refused as busy and sends nothing; the same curve applied twice sends the same nine frames and is confirmed both times"
    requirement: "WRITE-07"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aSecondWriteOperationDuringAnApplyIsRefusedAsBusyAndSendsNothing"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#theSameCurveAppliedTwiceSendsTheSameNineFramesAndIsConfirmedBothTimes"
        status: pass
    human_judgment: false
  - id: D6
    description: "Each of the five presets can be selected with one select frame, and the slot read back is returned"
    requirement: "WRITE-08"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#selectSlotSendsOneSelectFrameAndReturnsTheSlotReadBack"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#selectSlotTakesTheBackupFirstAndReportsTheSlotReadBack"
        status: pass
    human_judgment: false
  - id: D7
    description: "The backup file is written once, complete or not at all; a second save, twenty concurrent saves and an unreadable file all leave the existing bytes as they are"
    requirement: "WRITE-06"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/BackupStoreTests.swift#aSecondSaveReturnsFalseAndLeavesTheFileUnchanged"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/BackupStoreTests.swift#twentyConcurrentSavesLeaveExactlyOneWritersBackup"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/BackupStoreTests.swift#aFileThatIsNotJSONIsUnreadableAndLeftUntouched"
        status: pass
    human_judgment: false
  - id: D8
    description: "The backup is on disk before the first write frame of an apply or a preset switch; an unreadable backup stops apply, applyTestCurve, selectSlot and restore before anything is sent"
    requirement: "WRITE-06"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#applyWithoutAFileHasTheBackupOnDiskBeforeTheFirstWriteFrame"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#anUnreadableBackupStopsEveryWriteAndIsLeftUntouched"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#backupFromAFactorySlotReadsUser1AndPutsTheSlotBack"
        status: pass
    human_judgment: false
  - id: D9
    description: "Restore writes the backed-up curve to USER1, re-selects the slot recorded in the backup and is confirmed by read-back; an unconfirmed restore does not switch slots"
    requirement: "WRITE-06"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#restoreAfterTheTestCurvePutsTheOriginalUser1Back"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#restoreReselectsTheSlotThatWasActiveAtBackupTime"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#aRestoreThatIsNotConfirmedDoesNotSelectTheOriginalSlot"
        status: pass
    human_judgment: false
  - id: D10
    description: "applyTestCurve sends the nine pinned frames of the D-16 test curve and is confirmed"
    requirement: "WRITE-01"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#applyTestCurveSendsTheNinePinnedFramesAndIsConfirmed"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/JA11WriterTests.swift#theTestCurveKeepsTypeFrequencyAndQOfBandsTwoToFourAtZeroGain"
        status: pass
    human_judgment: false
  - id: D11
    description: "JA11Writer is the only public way to write; ja11-probe has no write command"
    verification:
      - kind: other
        ref: "! grep -Eq 'public func (apply|selectSlot|captureUser1|sendWrite)' Sources/JA11Kit/Device/JA11Device.swift; git diff --quiet cbbf4c3 -- Sources/ja11-probe/main.swift"
        status: pass
    human_judgment: true
    rationale: "The plan marks this prohibition as verified by judgment: the greps pass, but that no other path can write is a reading of the access levels, not something a test asserts."
  - id: D12
    description: "The real JA11 behaves as the in-memory dongle does: it accepts the frames, drops off USB or not after a save, and reads back what was sent"
    requirement: "WRITE-07"
    verification: []
    human_judgment: true
    rationale: "Nothing was sent to the real dongle in this plan. The first writes belong to plan 02-04."

# Metrics
duration: 9min
completed: 2026-10-10
status: complete
---

# Phase 2 Plan 02: Write Path Failure Handling, Backup and the Write Door Summary

**An apply that reports interruptions, silence and mismatches as what they are and survives a drop off USB after the save; a backup file written once through a hard link and never replaced; and `JA11Writer` as the only public way to write, with the backup taken first — all proven on the in-memory dongle, with nothing sent to the real JA11.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-10-10T15:39:14Z
- **Completed:** 2026-10-10T15:48:22Z
- **Tasks:** 2
- **Files modified:** 9 (4 created, 5 modified)
- **Tests:** 222 in 9 suites, all passing (plan 02-01 ended at 177 in 7)

## Accomplishments

- `JA11Device.apply(_:)` now has two regimes. Before the save, a failed send, a link that is down or a replugged dongle ends it with `.writeInterrupted`; no save goes out and no frame is sent again. After the save it waits for the dongle, selects USER1 and reads, until the reconnect timeout; then `.noReadBack`.
- One write operation at a time: a second `apply`, `selectSlot` or `captureUser1` is refused as `.busy` before anything is sent.
- `BackupStore.saveIfAbsent` writes the original USER1 contents once. An existing file is never replaced, whatever it holds.
- `JA11Writer` takes the backup before `apply`, `applyTestCurve` and `selectSlot`; `restore` loads the file before it sends anything. An unreadable file stops all four.
- Preset switching and the D-16 test curve are in place for the `ja11-eq` command of plan 02-03.

## Nothing was sent to the dongle, and the real backup location was not touched

No frame of any kind reached the JA11 while this plan was executed: only `swift build` and `swift test` were run, no executable was run, and every test uses `FakeTransport` / `FakeDongle`. No test creates an `HIDTransport`.

`~/Library/Application Support/JA11 EQ/` did not exist before the plan and does not exist after it. The file tests work in fresh directories under the temporary directory and remove them; none was left behind. One test reads `BackupStore.standard.fileURL.path` as a string and creates nothing.

`Sources/ja11-probe/main.swift` and `Package.swift` are byte for byte what they were at `cbbf4c3`.

## Pauses and timeouts chosen (for plan 02-04 to compare with the device)

| Setting | Default | Meaning |
|---|---|---|
| `framePause` | 100 ms | pause after every write frame |
| `saveSettle` | 1500 ms | extra wait after the save, before the first read-back round |
| `reconnectTimeout` | 10 s | counted from the save; how long a read-back may still arrive |
| `readBackRetryWait` | 200 ms | wait before the next round when the device is not usable yet (new init parameter) |
| link poll | 10 ms | how often the link is looked at while the dongle is away (fixed) |
| `replyTimeout` | 1 s | per read request, unchanged from Phase 1 |

The first read-back round therefore starts about 1.6 s after the save. A round that begins just before the deadline may finish after it; with a silent device the apply can end up to one `replyTimeout` late.

`ApplyReport.linkEvents` holds every disconnect and connect seen between the save and the return, with the seconds since the save. That is what plan 02-04 reads to answer D-19's question about re-enumeration.

## Errors the read-back loop treats as "not usable yet"

After the save, these lead to another round after `readBackRetryWait`:

- `.disconnected`
- `.notConnected`
- `.noReply`
- `.busy` (the watcher's own read after a reconnect competes for the device)
- `.transport(.notConnected)`
- `.transport(.sendFailed)`

Any other error ends the apply with that error, for example `.unexpectedReply` or `.transport(.refusedFrame)`. In each round only the select frame for USER1 is sent, then a full read. Pre-gain, count, filter and save frames are never sent a second time.

## captureUser1() goes beyond the letter of D-13

D-13 says the tool switches to slot 3 to read USER1 when another slot is active, and records that slot. `captureUser1()` also selects the recorded slot again afterwards and requires the device to report it, so taking a backup leaves the device as it was found. From a factory slot a backup therefore sends two write frames, select 3 and select of the original slot; with USER1 active it sends none.

It throws `.unexpectedReply`, and no file is written, when the active slot is not one of the five known presets (nothing is sent then), when the device does not switch to USER1, when USER1 does not hold exactly five filters of known type, or when the device does not switch back. In the third case the original slot is not re-selected: the state check comes before the switch back, as the plan orders it, so a dongle that was in a factory slot and reports an unusable USER1 is left in USER1.

## Task Commits

1. **Task 1 (tracer): apply failure handling and preset switching** — `647177e` (feat)
2. **Task 2: backup, restore and the write door** — `d1145a4` (test, RED), `50a39d5` (feat, GREEN)

Tracer feedback gate: interactive run, `human_verify_mode: end-of-phase`, automated-only verify. The tracer's verify was re-run and passed (the apply suite five times in a row) before Task 2 began.

## TDD record

- **Task 1** is a tracer, not a `tdd="true"` task. Its tests and its implementation were written together and the suite was run once, green: 195 tests in 7 suites. The plan asks for the drop-and-reconnect test to be written first and seen failing; that was not done, and it would not have failed. Plan 02-01's loop already retried on every `JA11Error`, so that path already ended confirmed. What this task changed is what happens before the save and which errors are retried after it, and those tests were not run against the old code.
- **Task 2 RED:** signatures with stub bodies. The run recorded 24 issues across `BackupStoreTests` and `JA11WriterTests` (22 failed expectations and 2 errors thrown by stubs), then stopped without a summary line: the test for a short original curve indexed band 4 of the stub's result, which had no bands. The failures seen before that are for the planned behaviour (no file written, no error raised, wrong test curve). **GREEN:** 222 tests in 9 suites.
- No refactor commit.
- `gsd-tools check tdd-red-evidence` was not run: it cannot parse Swift Testing's console output (see 02-01). The plan is `type: execute`, so the plan-level TDD gate does not apply.

## Files Created/Modified

- `Sources/JA11Kit/Backup/BackupStore.swift` — `DeviceBackup`, `BackupError`, `BackupStore`
- `Sources/JA11Kit/Device/JA11Writer.swift` — `JA11Writer`, `BackupOutcome`, `SlotReport`, `RestoreReport`
- `Sources/JA11Kit/Device/JA11Device.swift` — `apply` completed, `selectSlot`, `captureUser1`, the write flag, `readBackRetryWait`
- `Sources/JA11Kit/Model/EQCurve.swift` — `EQCurve.testCurve(basedOn:)`
- `Tests/JA11KitTests/FakeDongle.swift` — per-slot contents, `AfterSave`, `ignoresFilters`, `gainError`, `filterCount`, `typeOverride`, `onWrite`
- `Tests/JA11KitTests/JA11DeviceTests.swift` — `FakeTransport.sendError`, `failSends(with:afterSuccessful:)`
- `Tests/JA11KitTests/ApplyTests.swift` — 22 tests (was 4)
- `Tests/JA11KitTests/BackupStoreTests.swift` — 9 tests, `JA11WriterTests.swift` — 18 tests

## Decisions Made

See `key-decisions` in the frontmatter. In addition:

- The backup file is pretty-printed JSON with sorted keys and ISO 8601 dates. One test loads a file written by hand in that shape, so the shape on disk is pinned and not only round-tripped.
- The temporary file is flushed to disk (`synchronize`) before the link is made. It is the only copy of the original USER1 contents.
- `BackupOutcome` has a `backup` property that gives the backup of either case; `DeviceBackup` has a public initialiser.
- `SlotReport` and `RestoreReport` have no public initialiser: only the library makes them.
- `JA11Error.busy` now reads "Another operation on the JA11 is still in progress.", since it also covers writes.
- `apply` checks busy before not-connected, so a second caller is told the truth about why nothing was sent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] captureUser1 checks the slot of the state it read**
- **Found during:** Task 2
- **Issue:** The plan confirms the switch to USER1 by one slot read and then reads the state. A state read while the device had moved to another slot would have been saved as USER1's contents.
- **Fix:** `captureUser1()` throws `.unexpectedReply` when the state it read reports a slot other than 3.
- **Files modified:** `Sources/JA11Kit/Device/JA11Device.swift`
- **Committed in:** `50a39d5`

**2. [Rule 2 - Missing critical] The backup is flushed to disk before it gets its final name**
- **Found during:** Task 2
- **Issue:** Without a flush, a crash or power loss shortly after the link could leave a final file with incomplete contents, which every later run would then refuse as unreadable.
- **Fix:** `synchronize()` on the temporary file before `link`.
- **Files modified:** `Sources/JA11Kit/Backup/BackupStore.swift`
- **Committed in:** `50a39d5`

### Other differences from the plan's text

- **Tracer test order:** not test-first; see the TDD record.
- **`readBackRetryWait` is an init parameter**, default 200 ms as the plan says. Tests set it to 20 ms so reconnect timeouts of 300 to 500 ms allow several rounds.
- **The in-memory dongle drops off at once on the save**, not a few ms after it. A drop that came later could land after the read-back had already finished, and the test would then depend on timing.
- **`FakeDongle` now has contents per slot**, as Task 2 asks, and that was needed in Task 1 already. One 02-01 assertion changed with it: a dongle in the Vocal slot now reports the made-up factory filters, and USER1's contents are checked through `dongle.user1`.
- **Interruption tests use a 20 ms frame pause** so the link event is handled before the next frame is due. They assert the outcome (interrupted, no save, nothing sent afterwards), not the exact frame at which the apply stopped.

---

**Total deviations:** 2 auto-fixed (2 missing critical)
**Impact on plan:** No interface in the plan's `<interfaces>` block changed. No scope creep.

## Issues Encountered

- Two test closures failed to compile ("errors thrown from here are not handled"): a closure whose only `try` sits inside `#expect` is inferred as non-throwing. Fixed by taking the value with a plain `try` first.

## For plans 02-03, 02-04 and Phase 3

- **A busy device at the start of an apply is reported as `.writeInterrupted`.** `apply` reads the active slot first, and the plan turns any error there into `.writeInterrupted`, with a text that says nothing was written. When `watch()` is running its read after a connect at that moment, the slot read is refused as busy and the apply ends that way. Nothing was sent, and the text says so, but the caller sees an interruption where it could simply try again. `ja11-eq` does not use `watch()`, so this matters for the Phase 3 app only.
- **A process killed between the first value frame and the save** leaves the dongle's working copy partly changed until the next apply, restore or replug. The plan flags this and nothing here handles it.
- **A restore that is not confirmed leaves USER1 active**, even when the backup names another slot.

## User Setup Required

None - no external service configuration required.

## Verification

- `swift build` exits 0; `swift test`: `Test run with 222 tests in 9 suites passed`, three times in a row
- `swift test --filter ApplyTests`: 22 tests passed, eight runs in a row over both tasks
- `swift test --filter 'BackupStoreTests|JA11WriterTests'`: 27 tests passed, and the real backup file was absent afterwards
- `git diff --quiet cbbf4c3 -- Sources/ja11-probe/main.swift Package.swift` succeeds
- No `public func apply|selectSlot|captureUser1|sendWrite` in `JA11Device.swift`; `saveToUser1()` appears once there; `public func` appears five times in `JA11Writer.swift`
- `link(` is in `BackupStore.swift`; `removeItem|replaceItem|moveItem` appears once, for the temporary file
- Every acceptance criterion of both tasks was run and passed

## Next Phase Readiness

- Ready for plan 02-03: `JA11Writer` has the five operations the `ja11-eq` subcommands need, and each returns a report that says what was sent and what was read back.
- `requirements-completed` copies the plan's list. WRITE-06 and WRITE-08 are complete in the library. WRITE-01, WRITE-02, WRITE-04 and WRITE-07 are proven on the in-memory dongle only and await the run on the real dongle in plan 02-04.
- Still open, for plan 02-04 on the device: whether the JA11 accepts write frames with `00` before `EE`; whether it drops off USB after a save and for how long; whether 1.6 s after the save is early enough or too early for a read; whether selecting a factory slot and reading shows that slot's filters, which the in-memory dongle assumes.

## Self-Check: PASSED

- All 4 created files exist on disk.
- Commits `647177e`, `d1145a4`, `50a39d5` are in `git log`.
- `commits: 3` is measured: `git rev-list --count 18530f4..50a39d5`.

---
*Phase: 02-eq-engine-and-write-path*
*Completed: 2026-10-10*
