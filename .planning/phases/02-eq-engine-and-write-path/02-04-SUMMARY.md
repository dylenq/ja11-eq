---
phase: 02-eq-engine-and-write-path
plan: 04
subsystem: write-path
tags: [device, hid, write, backup, restore, verification]

requires:
  - phase: 02-eq-engine-and-write-path
    provides: "Plans 02-01 to 02-03: EQCurve, JA11Writer, BackupStore, ja11-eq"
provides:
  - "02-DEVICE-LOG.md: every command run against the real JA11 in plan 02-04, with full output and exit status"
  - "Device findings D-19: re-enumeration timing, x10 pre-gain scale, negative gain, factory presets readable, trailing byte"
  - "Backup file of the original USER1 on this Mac"
affects: [phase-3-apply-button, phase-4-readme-restore]

actuals:
  tokens: 10400
  tasks: 3
  commits: 1
plan_head_before: ff3b24cf725534507a524e6fdff784144c9ea0c4
plan_head_after: cefbe36

tech-stack:
  added: []
  patterns:
    - "Device procedure run through the committed binaries only, logged by a wrapper that appends command, output and exit status"

key-files:
  created:
    - .planning/phases/02-eq-engine-and-write-path/02-DEVICE-LOG.md
  modified: []

key-decisions:
  - "The three tasks share one log file and were committed together in one commit after the last task, because the log is the only artifact and the device steps were run in one continuous session"

requirements-completed: ["WRITE-01", "WRITE-02", "WRITE-04", "WRITE-06", "WRITE-07", "WRITE-08"]

coverage:
  - id: D1
    description: "Original USER1 contents and active slot saved to the backup file before any SET frame, equal to what ja11-probe read"
    requirement: "WRITE-06"
    verification:
      - kind: other
        ref: "ja11-eq backup original: lines diff against .build/ja11-device/baseline.txt: identical; log order check awk passes"
        status: pass
    human_judgment: false
  - id: D2
    description: "Preset switched away and back (Off, USER1) and to Vocal, Classic, Bass, each confirmed by slot read-back"
    requirement: "WRITE-08"
    verification:
      - kind: other
        ref: "02-DEVICE-LOG.md Step 2 and Factory presets before/after: result: confirmed on every slot switch"
        status: pass
    human_judgment: false
  - id: D3
    description: "Test curve written to USER1, USER1 made active, read-back identical to what was sent"
    requirement: "WRITE-01"
    verification:
      - kind: other
        ref: "02-DEVICE-LOG.md Step 4: result: confirmed, no diff:, ja11-probe prints the eight expected lines"
        status: pass
    human_judgment: false
  - id: D4
    description: "Restore put USER1 and the active slot back to the original, confirmed by read-back and an independent probe"
    requirement: "WRITE-06"
    verification:
      - kind: other
        ref: "02-DEVICE-LOG.md Step 5 and Final state: ja11-probe twice equals baseline"
        status: pass
    human_judgment: false
  - id: D5
    description: "Factory presets Vocal, Classic, Bass read identically before the first apply and after the restore; no save frame for a slot other than 3"
    requirement: "WRITE-04"
    verification:
      - kind: other
        ref: "cmp of vocal/classic/bass-before.txt and -after.txt; all 3 'tx: aa 0a 00 00 19' frames are 'aa 0a 00 00 19 01 03 00 ee'"
        status: pass
    human_judgment: false
  - id: D6
    description: "The dongle re-enumerates after a save and ja11-eq waits it out"
    requirement: "WRITE-07"
    verification:
      - kind: other
        ref: "link: disconnected +0.92s / link: connected +1.82s in three saves; each followed by a confirmed read-back"
        status: pass
    human_judgment: false
  - id: D7
    description: "The curve persists across an unplug and replug, and the test curve is audible as a bass lift"
    requirement: "WRITE-03"
    verification: []
    human_judgment: true
    rationale: "Needs a physical unplug and ears. Handed to the user; see Pending human verification."

duration: 25min
completed: 2026-10-10
status: complete
---

# Phase 2 Plan 04: First Contact With Writes on the Real JA11 Summary

**All five D-17 steps ran on the real dongle with no unexpected result: backup, preset switch away and back, identity apply, test curve and restore each confirmed by read-back, the factory presets read identically before and after, and the JA11 ends in its original USER1 state on slot 3.**

## Outcome

The plan ran to the end without hitting the stop rule. 37 SET frames were sent and the dongle accepted all of them with `00` in the byte before `EE`. The dongle dropped off USB after each of the three saves and `ja11-eq` waited it out. No source file was changed (`git status --porcelain -- Sources Package.swift Tests` is empty).

## Dongle state at the end

Final `ja11-probe` output (run twice, both equal to the baseline taken before the first command):

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

Backup file: `/Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json` (created 2026-10-10T18:22:11Z by `ja11-eq --raw backup`, never touched again; `ja11-eq backup` at the end still prints the same `backup-time:`).

## Findings (D-19)

These are the paragraphs of the device log, word for word.

**Re-enumeration.** Yes. After each of the three saves (identity apply, test curve, restore) the JA11 dropped off USB 0.92 s after the save frame and was back 1.82 to 1.83 s after it, away for about 0.9 s. `ja11-eq` waited this out by itself, reported it as `link: disconnected` and `link: connected` lines, and read back afterwards, so the recovery path was exercised on the real dongle (WRITE-07). No later probe found the dongle missing.

**Pre-gain scale.** The x10 scale holds. -6.0 dB was sent as `ff c4` and read back as -6.0 dB; +0.0 dB read back as +0.0 dB.

**Negative gain.** -3.0 dB (filter 1) was sent as `ff e2` and read back as -3.0 dB. The +6.0 dB of filter 0 was sent as `00 3c` and read back as +6.0 dB.

**Factory presets.** Yes: selecting a slot makes its filters readable. Vocal, Classic, Bass and Off each returned five peak filters that differ from USER1's and from one another (Off: 1000, 2000, 5000, 8000 and 10000 Hz, Q 0.70, flat). Their readings after the write and restore are byte-identical to their readings before. Pre-gain was +0.0 dB in all of them. The only save frames in the log carry `19 01 03`.

**Trailing byte.** None of six hypotheses (sum, two's complement and XOR, each over all preceding bytes or over the payload only) fits any of the eight baseline replies. The byte is not even a function of the frame content: the slot reply `16 01 03` carried `bd` in the baseline and `45` after the first save, and the other seven replies kept their bytes. SET frames with `00` in that position were accepted by the dongle on every one of the 37 SET frames sent.

**Reply to SET frames.** None. No `rx:` line directly follows any SET `tx:` line; replies only answer GET frames.

**Timing.** An apply takes about 4 s wall clock end to end (measured around the tool call): the write frames, the 0.92 s to drop-off, the dongle back at about 1.8 s, and the read-back after the settle. The dongle was away for about 0.9 s; the 1.6 s settle after the save was enough for a successful read-back in all three saves.

**Not examined in this phase.** Whether a filter write is audible before the save (v2 CONV-02), and whether the on-board EQ is active at 352.8 kHz, which only the audible check can show (v2 CONV-04).

## Phase 2 open questions (STATE.md Blockers/Concerns), answered from the evidence

- **Pre-gain scale (x10):** confirmed by read-back (`ff c4` reads -6.0 dB). By ear: not examined, see pending check 1.
- **Drop off USB after a save (WRITE-07):** yes, for about 0.9 s starting 0.92 s after the save; `ja11-eq` recovered each time.
- **Audible at 352.8 kHz / filter write audible before save:** not examined.
- **Factory preset filters readable by selecting its slot (WRITE-04):** yes; all four other slots return distinct filter sets, identical before and after.
- **Command-line way to write that leaves `ja11-probe` read-only:** `ja11-eq` is that; `ja11-probe` was only ever used for GET frames in this plan (its output contains no SET `tx:` line).
- **Undocumented byte before EE:** not a checksum of the tried kinds, and not a pure function of content (slot reply changed bd -> 45 after a save). SET frames with `00` there are accepted.

## What was sent to the dongle

Counted from the log: 12 `ja11-probe` runs (GET only; includes the raw baseline run) and 16 `ja11-eq` runs: 3 `backup` (the raw one that created the file, one plain, one at the end; none sent a SET frame), 10 `slot`, 2 `restore` and 1 `apply --test-curve`.

SET frames (`tx: aa 0a`), by command byte, 37 in total:

| Command | Meaning | Count |
|---|---|---|
| 16 | select slot | 13 |
| 17 | pre-gain | 3 |
| 18 | filter count | 3 |
| 15 | filter write | 15 |
| 19 | save (all `01 03`) | 3 |

No SET frame has a command byte outside 15 to 19. The log's `## Step 1: backup` section precedes the first `tx: aa 0a` line.

## Pending human verification

These need ears and hands and were not run or simulated. With the dongle currently in its original state:

1. Audible check. Play music through the JA11, then from the repo root:
   `"$(swift build --show-bin-path)/ja11-eq" apply --test-curve`
   Expect `result: confirmed`, bass lifted and the level a little lower than with Off. Compare with `"$(swift build --show-bin-path)/ja11-eq" slot off` and `"$(swift build --show-bin-path)/ja11-eq" slot user1`. If nothing is audible, set the JA11's format to 48 kHz in Audio MIDI Setup and report which sample rates the EQ was audible at.
2. Replug persistence. With the test curve still applied, unplug the JA11, wait about 3 seconds, plug it back in, then `"$(swift build --show-bin-path)/ja11-probe"`. Expect `slot: 3 (USER1)`, `pre-gain: -6.0 dB`, `filter 0: low-shelf 100 Hz +6.0 dB Q 0.70`, `filter 1: peak 1000 Hz -3.0 dB Q 1.00`.
3. Restore. `"$(swift build --show-bin-path)/ja11-eq" restore`, then `"$(swift build --show-bin-path)/ja11-probe"`. Expect `result: confirmed` and the original values (pre-gain +0.0 dB, five filters at +0.0 dB).

## Deviations from Plan

### Format departures (not device results)

Per 02-03-SUMMARY's departures, line-by-line checks of the plan were adapted and judged by substance (exit status, `read:` values, `result: confirmed`, independent `ja11-probe` read):

- `backup` prints no `result:` line; it was judged by exit 0, the file's content and the diff of its `original:` lines against the baseline.
- `sent:` lines print after the operation, so in raw output the `tx: aa 0a` frames precede them.
- `restore` prints `backup: kept ...` first.
- `slot` prints no `diff:` line.
- The plan's "eight `sent:` lines" for the test curve and the other expectations held as written.

### Other

- **Task commits:** the three tasks changed a single new file, the device log, and were committed together in one commit (`cefbe36`) at the end instead of one commit per task. The log content is ordered by task.
- **Extra logged probes:** one extra `ja11-probe` before the test curve (Step 4) and one before the restore (Step 5) were logged, as the plan asks, to show slot 3 active.

No auto-fix deviations; no source change.

## Known Stubs

None.

## Threat Flags

None.

## Issues Encountered

None. The first-ever write frames were accepted and nothing triggered the stop rule.

## Self-Check: PASSED

- `.planning/phases/02-eq-engine-and-write-path/02-DEVICE-LOG.md` exists; contains all 11 sections; 28 `exit:` lines all `exit: 0`; 13 `result: confirmed` lines.
- Commit `cefbe36` is in `git log`; `commits: 1` measured as `git rev-list --count ff3b24c..cefbe36`.
- Backup file exists; final probe equals baseline.
