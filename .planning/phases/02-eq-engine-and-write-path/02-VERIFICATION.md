---
phase: 02-eq-engine-and-write-path
verified: 2026-10-10T20:00:00Z
status: passed
score: 10/10 must-haves verified
covered_files:
  - Sources/JA11Kit/Backup/BackupStore.swift
  - Sources/JA11Kit/DSP/EQResponse.swift
  - Sources/JA11Kit/Device/JA11Device.swift
  - Sources/JA11Kit/Device/JA11Writer.swift
  - Sources/JA11Kit/HID/HIDTransport.swift
  - Sources/JA11Kit/Model/EQCurve.swift
  - Sources/JA11Kit/Model/EQModel.swift
  - Sources/JA11Kit/Protocol/FiioFrame.swift
  - Sources/JA11Kit/Protocol/JA11Commands.swift
  - Sources/ja11-eq/main.swift
  - Sources/ja11-probe/main.swift
  - Tests/JA11KitTests/ApplyTests.swift
  - Tests/JA11KitTests/BackupStoreTests.swift
  - Tests/JA11KitTests/EQCurveTests.swift
  - Tests/JA11KitTests/EQResponseTests.swift
  - Tests/JA11KitTests/FakeDongle.swift
  - Tests/JA11KitTests/FiioFrameTests.swift
  - Tests/JA11KitTests/HIDTransportErrorTests.swift
  - Tests/JA11KitTests/JA11DeviceTests.swift
  - Tests/JA11KitTests/JA11WriterTests.swift
  - Tests/JA11KitTests/SetFrameTests.swift
covered_digest: "v2:sha256:720a2ccb8ffa04ee81f4d39dcca70567694f9a599c943d637e05df97a7985ee7"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Audibility. Run `ja11-eq apply --test-curve` (low-shelf 100 Hz +6 dB, peak 1 kHz -3 dB, pre-gain -6 dB) with music playing through the JA11, then `ja11-eq restore`."
    expected: "The bass lift and the 1 kHz dip are audible while the test curve is active, and the sound returns to the original after restore."
    why_human: "Only a listener can confirm the on-board EQ changes playback (ROADMAP SC1 'can be heard'). Not done in plan 02-04."
  - test: "Persistence across replug (WRITE-03). Apply the test curve, unplug the JA11 from USB, plug it back in, run `ja11-probe`. Then run `ja11-eq restore`."
    expected: "After replug the probe prints slot 3 (USER1), pre-gain -6.0 dB, filter 0 low-shelf 100 Hz +6.0 dB Q 0.70, filter 1 peak 1000 Hz -3.0 dB Q 1.00. After restore, the probe equals the original (pre-gain +0.0, all gains 0.0)."
    why_human: "Needs a physical unplug. The 0.9 s re-enumeration that ja11-eq saw after each save is a firmware drop, not a user-driven power cycle, so it does not prove the curve persists."
---

# Phase 2: EQ Engine and Write Path Verification Report

**Phase Goal:** A 5-band curve with pre-gain can be written to the DAC's USER1 slot safely, clamped to device limits, confirmed by read-back, kept across a replug, with the original USER1 recoverable and the factory presets untouched.
**Verified:** 2026-10-10
**Status:** human_needed
**Re-verification:** No, initial verification

No code gap was found. Two items need the owner: audibility and the physical-replug check.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1a | CLI writes a 5-band + pre-gain curve, USER1 becomes active, read-back matches | VERIFIED | `JA11Device.apply` (JA11Device.swift:303) selects USER1, sends pre-gain, count, 5 filters, save, then `readState()` and `differences(from:)`. Device log Step 4: `apply --test-curve` exit 0, `result: confirmed`; an independent `ja11-probe` printed the test curve. |
| 1b | A mismatch is reported, not passed as success | VERIFIED | `ApplyReport.isConfirmed` and `differences` (EQCurve.swift:169, JA11Device.swift:85). `ja11-eq` has exit status 5 for mismatch (--help). ApplyTests cover mismatch with the in-memory dongle. Not seen on hardware, which is expected. |
| 1c | The change can be heard | HUMAN | Not done. See human item 1. |
| 2a | After unplug and replug the same curve reads back | HUMAN (WRITE-03) | Not done. See human item 2. |
| 2b | After a drop off USB following the save, the link recovers and state is re-read | VERIFIED | Apply loop with deadline, reconnect wait, one select frame, and `readState` (JA11Device.swift:340-364). Device log: three real saves each showed `link: disconnected +0.92s`, `link: connected +1.8s`, then a confirmed read-back with no restart. Tests: ApplyTests drop, silent and never-returns cases. |
| 3 | Original USER1 is saved to a file before the first write; restore puts it back, confirmed | VERIFIED | `JA11Writer.apply`, `applyTestCurve` and `selectSlot` all call `backup()` first (JA11Writer.swift). `saveIfAbsent` never replaces the file. The backup file exists, `formatVersion` 1, `activeSlot` 3, and its values equal the baseline. Device log Step 5: `restore` exit 0, confirmed, and the probe equals baseline. The live probe I ran now matches. |
| 4a | Preset switch between Vocal, Classic, Bass, USER1, Off, each confirmed by read-back | VERIFIED | `JA11Writer.selectSlot` returns `SlotReport.isConfirmed`. Device log: all five slots switched with `result: confirmed`. |
| 4b | A save to any slot other than 3 is refused | VERIFIED | The only save builder is `saveToUser1`. The transport gate `isPermittedFrame` is checked in `HIDTransport.send` before IOKit (HIDTransport.swift:145). `isSetRequest` is an allow-list. SetFrameTests "The gate refuses" suite passes. All 37 SET frames in the log carry `19 01 03` for saves. |
| 4c | Vocal, Classic and Bass read the same before and after a write and restore | VERIFIED | Device log "Factory presets before/after" records are byte-identical. Their contents are distinct from USER1 and Off, so the comparison is meaningful. |
| 5 | `swift test` without the device shows clamping, the PROJECT.md reference frame, response math, and auto pre-gain | VERIFIED | I ran `swift test`: 222 tests in 9 suites pass. Clamping in `EQCurve.clamped()` and in the `setFilter`/`setPreGain` builders. The reference frame is checked in SetFrameTests. `autoPreGain` (EQResponse.swift:121) is clamped to -12...0 and rounded toward more attenuation. |

Score: 8 of 10 requirement-level must-haves verified; the other 2 depend on the human checks (audible part of WRITE-01 criterion, and WRITE-03).

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| WRITE-01 | Write 5 bands + pre-gain to USER1, make active | SATISFIED (audibility pending) | Device log Step 4; probe confirms |
| WRITE-02 | Read back and report mismatch | SATISFIED | `ApplyReport.differences`, exit 5, tests |
| WRITE-03 | Curve survives unplug and replug | NEEDS HUMAN | REQUIREMENTS.md still marks it Pending, consistent with this report |
| WRITE-04 | Factory presets never modified, only slot 3 written | SATISFIED | Gate, single save builder, byte-identical factory readings |
| WRITE-05 | Clamp to device limits before sending | SATISFIED | `clamped()` plus builders, `isSetRequest` range checks, tests |
| WRITE-06 | Original USER1 saved before first write, restorable | SATISFIED | Backup file, restore in log |
| WRITE-07 | Link recovers after a post-save drop | SATISFIED | Three real recoveries in the device log, plus tests |
| WRITE-08 | Switch preset among five | SATISFIED | Log and writer |
| WRITE-09 | Combined response of peak, low shelf, high shelf | SATISFIED | `EQResponse.swift` plus EQResponseTests |
| WRITE-10 | Auto pre-gain within -12...0 | SATISFIED | `autoPreGain()` plus tests |

No orphaned requirements: WRITE-01 to WRITE-10 are all claimed by plans and mapped in REQUIREMENTS.md.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Package builds | `swift build` | Build complete | PASS |
| Tests | `swift test` | 222 tests, 9 suites, all pass | PASS |
| Read-only probe against the real dongle | `ja11-probe` | slot 3, pre-gain +0.0, five filters equal to baseline | PASS |
| Usage errors contact nothing | `ja11-eq slot bogus`, `ja11-eq apply --bogus` | exit 2 with usage | PASS |

I sent no write command to the dongle during this verification.

### Anti-Patterns Found

None blocking. I did not run a debt-marker scan across every file. The code I read had no stubs.

### Observations (not gaps)

- The trailing byte before `ee` in replies is not derivable from the content (device log findings); SET frames send `00` there and the dongle accepted all 37. Recorded as a finding, not acted on. It is a risk for later phases only if the firmware ever starts checking it.
- The load-bearing evidence for the on-device criteria is the executor's device log. I cross-checked it against the live probe and the backup file, and the log is internally consistent (identical read frames across runs, save frames all `19 01 03`). I could not independently re-run the writes, per the constraints.

### Human Verification Required

1. **Audibility.** Run `ja11-eq apply --test-curve` while playing music through the JA11, listen for the bass lift and the 1 kHz dip, then run `ja11-eq restore`. Expected: audible change, then back to normal.
2. **Persistence across replug (WRITE-03).** Apply the test curve, unplug the JA11, plug it back in, run `ja11-probe`. Expected: slot 3, pre-gain -6.0 dB, filter 0 low-shelf 100 Hz +6.0 dB Q 0.70, filter 1 peak 1000 Hz -3.0 dB Q 1.00. Then run `ja11-eq restore` and confirm the probe is back to the original (pre-gain +0.0, all gains 0.0).

### Gaps Summary

No gaps. The phase is code-complete and device-tested. It becomes passed once the two human checks are done and WRITE-03 is ticked in REQUIREMENTS.md. Leave the dongle in the original state afterward (`ja11-eq restore`).

---

_Verified: 2026-10-10_
_Verifier: Claude (gsd-verifier)_

## Human Verification Results (2026-10-11)

Performed by the user from Terminal.app on the real JA11; results reported in the main session.

| # | Check | Result |
|---|-------|--------|
| 1 | Test curve audible (WRITE-01) | Passed — user heard the bass lift. The on-board EQ is therefore active at the Mac's current output rate. |
| 2 | Curve persists across unplug/replug (WRITE-03) | Passed — user reported the curve was kept after replugging. |

Status changed from `human_needed` to `passed` on this basis.
