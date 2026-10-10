---
phase: 02-eq-engine-and-write-path
plan: 03
subsystem: write-path
tags: [swift, swiftpm, cli, hid, exit-status, json]

# Dependency graph
requires:
  - phase: 02-eq-engine-and-write-path
    provides: "Plan 02-01: EQCurve (Codable, deviceState()), ApplyReport, EQState.reportLines(). Plan 02-02: JA11Writer (backup, apply, applyTestCurve, restore, selectSlot), BackupStore.standard, BackupError, DeviceBackup"
provides:
  - ja11-eq executable product and target
  - Subcommands backup, apply <curve.json>, apply --test-curve, restore, slot <vocal|classic|bass|user1|off>, flags --raw and --help
  - Output prefixes backup:, backup-time:, original:, sent:, link:, read:, diff:, final:, state:, info:, result:
  - Exit statuses 0 to 6
affects: [02-04 first contact with writes, phase-4-readme-restore]

# Actuals (#2632)
actuals:
  tokens: 3760
  tasks: 2
  commits: 2
plan_head_before: ac979ddcd4ccab067f1bcec51231d1c7cb802575
plan_head_after: b0be1853fe3cdcf0159afd23e370475aaf0721a7

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Arguments, the curve file and the backup file are all checked before a transport exists"
    - "One function prints the result line and takes its answer from a report's isConfirmed"
    - "One HIDTransport creation site in the command; every write goes through JA11Writer"

key-files:
  created:
    - Sources/ja11-eq/main.swift
  modified:
    - Package.swift

key-decisions:
  - "ja11-eq checks the backup file before a transport exists: a file that is there but unreadable ends every subcommand with status 6, and restore without a file ends with status 6, in both cases without opening the device"
  - "The backup subcommand prints no result line; its exit status 0 means the backup exists and was printed"
  - "sent: lines are printed from the report after the operation returned, so an operation that ends in an error prints no sent: lines; the error text on stderr says what was and was not sent"
  - "A curve file is refused with status 2 when it is not a regular file, is larger than 64 KB, does not decode, or holds more than five bands"
  - "A restore whose final slot is not the one the backup names prints an extra diff: final slot line before the final: line"

patterns-established:
  - "CLI checks in this plan run only invocations that end before a transport exists"

requirements-completed: ["WRITE-01", "WRITE-02", "WRITE-06", "WRITE-08"]

coverage:
  - id: D1
    description: "ja11-eq builds, prints its usage with the five subcommand forms, both flags, the backup file's location and the exit statuses 0 to 6, and --help exits 0"
    verification:
      - kind: other
        ref: "swift build; \"$(swift build --show-bin-path)/ja11-eq\" --help | grep -q -- '--test-curve'"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every malformed invocation exits 2 and prints nothing to stdout: no command, unknown command, missing or surplus argument, a slot given as a number, in another case or as another word, an invalid argument next to --help"
    requirement: "WRITE-08"
    verification:
      - kind: other
        ref: "Task 1 and Task 2 verify: chk; chk slot; chk slot loud; chk slot 3; chk slot Vocal; chk apply; chk apply --test-curve extra.json; chk apply /nonexistent/ja11-curve.json; chk frobnicate; chk restore now; chk --help bogus"
        status: pass
    human_judgment: false
  - id: D3
    description: "A curve file that cannot be used is refused with status 2 and the cannot read curve file message before a transport exists: unknown filter type, missing file, a directory, a file larger than 64 KB"
    requirement: "WRITE-01"
    verification:
      - kind: other
        ref: "Task 1 verify: apply bad.json with type notch exits 2 with 'cannot read curve file' on stderr; also run by hand for a 70 KB file and a directory"
        status: pass
    human_judgment: false
  - id: D4
    description: "The invalid invocations did not reach the device path: the real backup file was neither created nor modified"
    requirement: "WRITE-06"
    verification:
      - kind: other
        ref: "Task 2 verify: marker-file check on ~/Library/Application Support/JA11 EQ/user1-original.json; the directory is absent after the plan"
        status: pass
    human_judgment: false
  - id: D5
    description: "The command goes through JA11Writer, creates a transport at exactly one place, uses applyTestCurve for the test curve, and ja11-probe is unchanged"
    verification:
      - kind: other
        ref: "grep -q JA11Writer Sources/ja11-eq/main.swift; grep -c 'HIDTransport()' prints 1; grep -q applyTestCurve; git diff --quiet cbbf4c3 -- Sources/ja11-probe/main.swift"
        status: pass
    human_judgment: false
  - id: D6
    description: "The five subcommands, run against a JA11, print the output contract's lines and end with the exit status that matches the outcome; result: confirmed appears only for a confirmed report"
    requirement: "WRITE-02"
    verification: []
    human_judgment: true
    rationale: "No ja11-eq subcommand was run with valid arguments in this plan, and no test covers the part of main.swift after the transport is created: it compiles and was read, nothing more. Plan 02-04 runs it on the real dongle, in a fixed order."

# Metrics
duration: 3min
completed: 2026-10-10
status: complete
---

# Phase 2 Plan 03: The ja11-eq Command Summary

**`ja11-eq` with five subcommands on top of `JA11Writer`: every argument, the curve file and the backup file are checked before a transport exists, what was sent and read back is printed, and each outcome has its own exit status from 0 to 6. The part that talks to the dongle compiles but has not been run.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-10-10T15:52:35Z
- **Completed:** 2026-10-10T15:55:00Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)
- **Tests:** 222 in 9 suites, all passing (unchanged; this plan adds no test)

## Accomplishments

- `Package.swift` has the executable product and target `ja11-eq`; the package still declares no dependency.
- `ja11-eq` rejects every malformed invocation and every unusable curve file with status 2, with nothing on stdout, before a transport or device object exists.
- Every subcommand reaches the dongle only through `JA11Writer`. The file has one `HIDTransport` creation site, builds no frame and calls no write function of its own.
- `result: confirmed` is printed in one function, which takes its answer from the report's `isConfirmed`.

## Not run against the dongle; the backup file was not created

No `ja11-eq` subcommand was run with valid arguments. The only invocations run were `--help`, usage errors and curve-file failures, each of which ends before a transport exists. `ja11-probe` was not run either. No frame of any kind reached the JA11 while this plan was executed.

`~/Library/Application Support/JA11 EQ/` did not exist before the plan and does not exist after it. This plan did not create the backup file; that happens in plan 02-04.

**What this means for the code:** everything in `main.swift` after the transport is created has been compiled and read, and never executed. No test covers it. Its first run is plan 02-04's first step.

## The usage text, as `ja11-eq --help` prints it

```text
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
backup file: /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
  written once, before the first write to the JA11, and never replaced
exit status: 0 confirmed by read-back (backup: the backup was printed), 1 no JA11 found,
  2 usage error or unreadable curve file, 3 access refused by macOS,
  4 device operation failed, 5 read-back mismatch, 6 backup problem
```

## What each subcommand prints (stdout)

| Subcommand | Lines, in order |
|---|---|
| `backup` | `backup: saved\|kept <path>`, `backup-time:`, eight `original:` lines |
| `apply <file>`, `apply --test-curve` | `backup:`, eight `sent:`, zero or more `link:`, eight `read:`, zero or more `diff:`, `result:` |
| `restore` | `backup: kept <path>`, eight `sent:`, `link:`, eight `read:`, `diff:`, `final: slot: N (Name)`, `result:` |
| `slot <name>` | `backup:`, `sent: slot: N (Name)`, `read: slot: N (Name)`, then `state:` lines or one `info: state not readable in this slot: <error>`, `result:` |

`link:` lines read `link: disconnected +0.42s`. `backup-time:` is ISO 8601 in UTC, for example `2026-10-10T15:04:05Z`. With `--raw`, `tx: ` and `rx: ` hex lines appear between the others as frames travel.

## Departures from the output contract

Plan 02-04 matches the output line by line, so each difference from the plan's contract is listed here:

1. **`backup` prints no `result:` line.** There is no read-back report to confirm, and the command prints `result: confirmed` only from a report's `isConfirmed`. Exit status 0 is what says the backup exists and was printed.
2. **`sent:` lines appear only when the operation returned a report.** They are printed from the report, after the operation. An apply, restore or preset switch that ends in an error prints no `sent:` line; the error text on stderr says what was and was not sent, and `--raw` shows the frames. The same holds for `slot`: `sent:` and `read:` come together after the switch.
3. **`restore` may print one extra line:** `diff: final slot: expected 0 (Vocal), read 3 (USER1)`, placed after the apply's `diff:` lines and before `final:`, when the device does not end in the slot the backup names. Without it a restore could end in `result: mismatch` with no `diff:` line.
4. **`restore` prints `backup: kept <path>` before the device is contacted**, as soon as the file has been loaded. With no JA11 plugged in the output is that one line and exit status 1.
5. **`slot` prints no `diff:` line.** A switch that is not confirmed shows in the `sent:` and `read:` lines and in `result: mismatch`.
6. **`--raw` prints `tx:` and `rx:` lines only.** The three `info:` lines that `ja11-probe --raw` adds (input-monitoring access, reply header offset, request frame form) are not printed here.
7. **`apply` and `slot` call `JA11Writer.backup()` first** to learn `saved` or `kept`, as the plan says. With no backup file and a factory slot active, that call sends two select frames (to USER1 and back) before the operation itself begins; `--raw` shows them.

## Exit statuses

| Status | Meaning | From |
|---|---|---|
| 0 | confirmed by read-back; for `backup`: the backup exists and was printed; `--help` | a report whose `isConfirmed` is true |
| 1 | no JA11 found | `JA11Error.notFound` |
| 2 | usage error or unreadable curve file | argument and file checks |
| 3 | macOS refused access | `JA11Error.transport(.accessDenied)` |
| 4 | the device operation failed | every other `JA11Error`, including `.writeInterrupted`, `.noReadBack`, `.noReply`, and any error of another kind |
| 5 | read-back mismatch, `result: mismatch` | a report whose `isConfirmed` is false |
| 6 | backup problem | any `BackupError` |

## Task Commits

1. **Task 1 (tracer): the command line, before any transport** — `a827586` (feat)
2. **Task 2: the five subcommands through JA11Writer** — `b0be185` (feat)

Tracer feedback gate: interactive run, `human_verify_mode: end-of-phase`, automated-only verify. The tracer's verify passed on the code as committed, and Task 2 began after it. Between the two commits a valid command ended with status 4 and a message, without creating a transport.

## Files Created/Modified

- `Sources/ja11-eq/main.swift` — the command (427 lines)
- `Package.swift` — product and target `ja11-eq`

## Decisions Made

See `key-decisions` in the frontmatter. In addition:

- Flags `--raw` and `--help` may stand anywhere. `--help` alone prints the usage and exits 0; with a valid command next to it, it prints the usage and exits 0 without running the command or reading the curve file; with anything invalid next to it, the error wins and the status is 2.
- A word that starts with `-` where a command or a curve file is expected is reported as an unknown option. A curve file whose name starts with `-` can be given as `./-name.json`.
- The curve file is opened once and at most 64 KB plus one byte are read, so a longer file is refused without being read whole. `stat` is used first, so a directory or a device node is refused by kind.
- A decoding failure names the place in the file, for example `bands.Index 0.type: unknown filter type "notch"; expected peak, lowShelf or highShelf`.
- A curve file with fewer than five bands is accepted. The library fills the missing positions with neutral bands (peak, 1000 Hz, 0.0 dB, Q 1.00), and the `sent:` lines show them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] A curve file with more than five bands is refused**
- **Found during:** Task 1
- **Issue:** `EQCurve.clamped()` keeps the first five bands and drops the rest without a word. A file with six bands would have been written to the dongle as something other than what the file says.
- **Fix:** `loadCurve` refuses such a file with `cannot read curve file '<path>': N bands, the JA11 has 5` and status 2, before a transport exists.
- **Files modified:** `Sources/ja11-eq/main.swift`
- **Verification:** read only; none of the plan's checks uses such a file
- **Committed in:** `a827586`

**2. [Rule 2 - Missing critical] The backup file is checked before a transport exists**
- **Found during:** Task 2
- **Issue:** As planned, an unreadable backup file, or a restore without a file, would have been found by `JA11Writer` only after the device had been opened. `restore` also has to print `backup: kept <path>`, which would not be true without a file.
- **Fix:** Before the transport is created: when the file exists it is loaded, for every subcommand; `restore` loads it in any case. A `BackupError` ends the command with status 6 and the device is not opened. `JA11Writer` still makes its own checks.
- **Files modified:** `Sources/ja11-eq/main.swift`
- **Verification:** read only; running it needs a valid invocation, which this plan does not make
- **Committed in:** `b0be185`

---

**Total deviations:** 2 auto-fixed (2 missing critical)
**Impact on plan:** Both refuse earlier and send nothing. No interface changed. The departures from the output contract are listed in their own section above.

## Issues Encountered

None.

## Verification

- `swift build` exits 0 with no warning; `swift test`: `Test run with 222 tests in 9 suites passed`
- `ja11-eq --help` exits 0 and names `backup`, `apply`, `--test-curve`, `restore`, `slot`, `--raw` and the statuses 0 to 6
- All eleven invalid invocations of the plan exit 2 with empty stdout, after Task 1 and again after Task 2; so do five more tried by hand (`slot VOCAL`, `slot user1 extra`, `backup now`, `--bogus`, `apply --bogus`)
- A curve file with filter type `notch` exits 2 with `cannot read curve file`; so do a 70 KB file and a directory
- `! grep -q '\.package(' Package.swift` succeeds
- `grep -c 'HIDTransport()' Sources/ja11-eq/main.swift` prints 1; `grep -c 'result: confirmed'` prints 1, inside `exitWithResult(isConfirmed:)`, whose four call sites all pass a report's `isConfirmed`
- `git diff --quiet cbbf4c3 -- Sources/ja11-probe/main.swift` succeeds
- The marker check of Task 2 passed and `~/Library/Application Support/JA11 EQ/` is absent
- No `ja11-eq` subcommand was run with valid arguments

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for plan 02-04: the command exists, its output and exit statuses are fixed as described above.
- Plan 02-04 should read the section on departures from the output contract before matching lines, in particular: no `result:` line for `backup`, and no `sent:` line when an operation ends in an error.
- `requirements-completed` copies the plan's list. WRITE-01, WRITE-02, WRITE-06 and WRITE-08 have their command-line part in place; whether the command behaves as described on the real dongle is what plan 02-04 finds out.
- Still open, for plan 02-04 on the device, unchanged from 02-02: whether the JA11 accepts write frames with `00` before `EE`; whether it drops off USB after a save and for how long; whether 1.6 s after the save is the right moment for a read; whether a factory slot's filters can be read after selecting it (the `state:` or `info:` lines of `slot` answer that).

## Self-Check: PASSED

- `Sources/ja11-eq/main.swift` exists on disk; `Package.swift` contains `ja11-eq`.
- Commits `a827586` and `b0be185` are in `git log`.
- `commits: 2` is measured: `git rev-list --count ac979dd..b0be185`.

---
*Phase: 02-eq-engine-and-write-path*
*Completed: 2026-10-10*
