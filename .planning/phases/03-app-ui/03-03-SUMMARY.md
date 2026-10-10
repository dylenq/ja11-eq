---
phase: 03-app-ui
plan: 03
subsystem: write-path-ui
tags: [swiftui, apply, presets, restore, serialisation]
requires: [03-01 AppModel, 03-02 CurveEditor, JA11Writer]
provides: [OperationState, OperationOutcome, AppModel.apply/selectPreset/revert/restore, PresetPickerView, ApplyBarView, Device menu]
affects: [04-packaging]
tech-stack:
  added: []
  patterns: [state set before first await for idempotency, deferred disconnect during operations, retry only on busy refusal]
key-files:
  created:
    - Sources/JA11EQCore/OperationState.swift
    - Sources/JA11EQ/PresetPickerView.swift
    - Sources/JA11EQ/ApplyBarView.swift
    - Tests/JA11KitTests/AppModelOperationTests.swift
    - Tests/JA11KitTests/AppModelPresetTests.swift
  modified:
    - Sources/JA11EQCore/AppModel.swift
    - Sources/JA11EQ/ContentView.swift
    - Sources/JA11EQ/JA11EQApp.swift
decisions:
  - "Dirty editor plus selecting the already-active preset does nothing (no confirmation)"
  - "A mismatched restore still reloads the editor from the DAC, so the editor shows what the DAC holds"
  - "Operation state is set before the first await; this alone makes a double press a no-op"
requirements-completed: [APP-02, APP-08]
metrics:
  tasks: 3
  tests: 302 passing in 16 suites (26 new)
status: complete
actuals:
  tokens: 40000
  tasks: 3
  commits: 3
plan_head_before: 6a3eb3a056550d085455706b0b718db45b2f634a
plan_head_after: 0e2260da5c39f15943cf35a3396464d3a92d2d59
---

# Phase 3 Plan 3: Apply, presets, revert, restore Summary

`AppModel` now applies, switches presets, reverts and restores the original USER1 curve, only through `JA11Writer.apply/selectSlot/restore`, with one operation at a time, the post-save USB drop hidden, and plain outcomes (confirmed / mismatch lines / error text) shown by new picker and apply-bar views.

## Commits
- 75ec6bb OperationState/OperationOutcome, apply(), serialisation, 13 operation tests
- 545d64c selectPreset/confirm/cancel, revert, restore request/confirm/cancel, 13 preset tests
- 0e2260d PresetPickerView, ApplyBarView, ContentView composition, Device > Restore Original...

## Required statements
- **Busy retry:** at most 10 attempts, 100 ms apart, only for the exact `JA11Error.busy` (nothing was sent); only at the start of apply and slot switch. Restore has no retry.
- **Quiet-link wait:** every operation polls every 20 ms for up to 5 s while the watch loop's read of a connect is in flight, before touching the writer.
- **Real dongle vs. in-memory (read only):** on launch the app stayed running 5 s against the real dongle; nothing differed that was visible without the GUI. Whether the real device ever returns `.writeInterrupted` against the watch loop's read is untested (no write was made); finding would go to the verifier, not a write retry.
- **Nothing wrote to the dongle or the real backup file.** All tests use `FakeDongle` and a temporary `BackupStore`; `~/Library/Application Support/JA11 EQ/user1-original.json` mtime was unchanged (1791656531) across the runs; the launch check only reads. Grep gate: the only writer calls in the app are `writer.apply`, `writer.restore`, `writer.selectSlot`; no file removal/replace/move in app sources; views reference no device or writer; JA11Kit, ja11-probe, ja11-eq and Package.swift are untouched.

## TDD / RED runs
- Task 1: first build of AppModelOperationTests failed to compile (`extra argument 'writer'`, no member `canApply`/`apply`); implemented; passed.
- Task 2: first build of AppModelPresetTests failed to compile (no member `selectPreset`, `revert`, `requestRestore`); implemented; passed.
- `check tdd-red-evidence` skipped (cannot parse Swift Testing output).

## Deviations from Plan
**1. [Rule 1 - Test race] Connect-wait tests were flaky** (about 11 of 15 runs failed): waiting for `connection == .connected` returned before the drop was processed, and a fast fake read finished before the operation began, so the reconnect reload legitimately replaced the edit. Fixed in the tests: wait for two new `statusLog` entries and slow the fake's read replies to 4 ms. 15/15 consecutive runs pass afterwards. No app change.
**2. [Rule 1 - Warning] `describe(_:)`** used an always-true cast; now switches on `JA11Error` / `BackupError`, else `localizedDescription`.
**3. [Added] `AppModel.activePreset`** (the DAC-reported `PresetChoice?`) so the picker needs no slot logic.
**4. [Interpretation]** A mismatched restore reloads the editor from the DAC (clean, showing what the DAC holds) while the outcome stays a non-success mismatch.

## Verification
- `swift build` clean, 0 warnings; `swift test` 302/302 in 16 suites; operation + preset suites 15 consecutive passes; app alive 5 s after launch, killed, no JA11EQ process left.

## Known Stubs
None.

## Human checks (pending, end of phase; these write to the real dongle once, by the user)
Run `swift run JA11EQ` with the JA11 plugged in (terminal may need Input Monitoring). The original USER1 backup is in `~/Library/Application Support/JA11 EQ/user1-original.json`; `Device > Restore Original...` puts it back.
1. Header and load: window opens in front; Connected, preset Custom (Phase 2 test curve), sample rate (e.g. 352.8 kHz or a dash); rows and graph show pre-gain -6.0, band 1 low shelf 100 Hz +6.0 Q 0.70, band 2 peak 1000 Hz -3.0 Q 1.00, three bands at 0 dB.
2. Unplug and replug: Not connected with Plug in the JA11, controls disabled; replug returns to Connected with the curve, no restart.
3. Editing: change frequency, gain, Q with sliders and fields; graph follows; toggle a band off/on; change type. Type 99 in a gain field and 0 in Q: snaps to 12.0 and 0.1.
4. Graph: gridlines/labels 20 Hz-20k, every 3 dB, distinct 0 dB line; drag handles (fields and curve follow); drag past edges stops at 20 Hz, 20 kHz, plus or minus 12 dB; Option-drag changes Q; a switched-off band's handle looks different and does not move.
5. Pre-gain: Auto on lowers pre-gain by itself, slider disabled; Auto off lets you move it; fainter line shows the pre-gain effect, parts above 0 dB marked as clipping risk.
6. Apply: with unsaved changes the label shows and Apply is enabled; press it; progress about 4 s, header does not flash Not connected; then Applied and confirmed and the unsaved label disappears; Apply is disabled afterwards.
7. Audible: play audio through the JA11 and hear the new curve (a big bass boost); `ja11-probe` in another terminal prints the applied values.
8. Presets: Vocal, Classic, Bass, Off, then Custom; header updates after each switch, factory filters read-only with the note and Apply disabled; Custom brings back your curve, editable. Edit first, then switch: a confirmation asks before discarding.
9. Revert: edit a value, press Revert; editor returns to the DAC's stored curve.
10. Restore original: button or Device menu, confirm; window reports original USER1 restored and confirmed; bands 59, 181, 704, 7171, 3973 Hz at 0.0 dB.
11. The dongle's volume and play/pause keys still control the Mac while the app is open.

## Self-Check: PASSED
All created files present; commits 75ec6bb, 545d64c, 0e2260d exist.
