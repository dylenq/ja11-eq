---
phase: 03-app-ui
verified: 2026-10-11T00:00:00Z
status: passed
score: 5/5 roadmap truths wired and test-backed; all five still need on-screen/real-device confirmation
covered_files: [Sources/JA11EQ/ContentView.swift, Sources/JA11EQCore/AppModel.swift, Sources/JA11EQCore/CurveEditor.swift, Sources/JA11EQCore/GraphGeometry.swift]
covered_digest: "v2:sha256:0463dd375e1049271301d82e92313c2cb55251a15f439a99201e08d58e97a279"
behavior_unverified: 0
human_verification:
  - test: "Run the 11-step script in 03-03-SUMMARY.md (header and load, unplug/replug, editing and clamping, graph drag, pre-gain Auto, Apply, audible result, presets, Revert, Restore original, volume/play keys)"
    expected: "Each step behaves as written; Apply ends with 'Applied and confirmed'; the Device menu restore puts the original USER1 back"
    why_human: "Layout, drag feel, real-dongle write and audible result cannot be checked without the GUI and the real hardware"
---

# Phase 3: App UI Verification Report

**Goal:** The user can see the DAC's state, edit the 5-band curve against a live response graph, and apply it to the DAC, all from one window.
**Status:** human_needed. No gaps were found in code or tests. Nothing visual or hardware-dependent was checked.
**Re-verification:** No (initial).

## Evidence run by the verifier
- `swift build` succeeded. `swift test` passed: 302 tests in 16 suites.
- The test suites that cover this phase are AppModelConnection, AppModelEditor, AppModelPreset, AppModelOperation, CurveEditor, GraphGeometry and SampleRate.
- No TBD, FIXME, XXX or TODO markers in `Sources/JA11EQ` or `Sources/JA11EQCore`.
- `Sources/JA11EQ` contains no reference to JA11Writer, FiioFrame, JA11Device or HIDTransport. Views talk only to `AppModel`.
- Since the phase began, the only change to JA11Kit, ja11-probe, ja11-eq and Package.swift is 4 added lines in Package.swift (the new targets).
- The real backup `user1-original.json` was last modified Oct 10 23:52, before this pass. I did not touch it.
- I ran no device command, no `ja11-probe`, and did not touch the running app.

## Observable truths (roadmap success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Header shows connection, active preset and sample rate; editor loads the DAC curve; replug reloads | wiring VERIFIED, on-screen check pending | `ContentView` header renders `connection.title`, `activePresetTitle` and `sampleRateText`. `AppModel.handle` loads the editor on `.state` and tracks the sample rate via `rates()`. Covered by the AppModelConnection and AppModelEditor tests. Visuals and a real unplug/replug are human items. |
| 2 | Preset picker switches the DAC preset and the header shows the new one | wiring VERIFIED, real device pending | `PresetPickerView` calls `selectPreset`, which goes through `writer.selectSlot` and then `device.readState()`. The header shows the slot the DAC reports. The AppModelPreset tests use FakeDongle. |
| 3 | Per-band type, frequency, gain, Q and on/off; the graph redraws | wiring VERIFIED, visuals pending | `EditorPanelView` binds sliders, text fields, a type Picker and an on/off Toggle to clamping `CurveEditor` setters. `GraphView` renders from `model.editor.curve`. CurveEditor and GraphGeometry tests pass. |
| 4 | Dragging a handle changes frequency and gain; pre-gain is manual or Auto | wiring VERIFIED, drag feel pending | `GraphView` DragGesture calls `hitTest` and then `moveBand`; Option-drag calls `scaleQ`. The pre-gain slider and Auto toggle are bound to `setPreGain` and `setAutoPreGain`. Tests exist at the model level. The gesture itself is a human item. |
| 5 | Apply sends the curve and shows whether the read-back confirmed it | wiring VERIFIED, real write pending | `ApplyBarView` calls `AppModel.apply`, which calls `writer.apply` and then sets `.confirmed` and `markApplied` only when `report.isConfirmed`. A mismatch gives `.mismatch(differences)` and an error gives `.failed`. The editor is not marked clean on mismatch. AppModelOperation tests (FakeDongle) pass. |

No truth is FAILED. Truths 1 to 5 each have behaviour that only a human can confirm on screen or on the dongle, so none is claimed fully verified.

## Prohibitions
- Judgment-tier items (no CoreAudio writes, no third-party dependencies): no violation found. Package.swift gained only local targets. These are non-authoritative and listed for human review.
- Test-tier items are enforced by passing tests:
  - Values clamped: CurveEditor tests.
  - Read-only editor ignores edits: CurveEditor and AppModel tests.
  - Bands not reordered: CurveEditor tests.
  - Dirty edits not discarded on a non-reconnect reload: AppModelEditor tests.
  - Mismatch not shown as success: AppModelOperation tests.
  - Post-save drop not shown as unplugged: `deferredDisconnect` logic, exercised by tests.
  - One operation at a time: state is set before the first await, and busy retry applies only to `JA11Error.busy`.
- The no-real-dongle-write rule for automated checks is satisfied. Tests use FakeDongle and a temporary BackupStore.

## Requirements coverage
APP-01 to APP-10 are all claimed by the plans. REQUIREMENTS.md maps all ten to Phase 3, so there are no orphans.

| Requirement | Status |
|---|---|
| APP-01 | Wired and tested (header connection and preset). On-screen check pending. |
| APP-02 | Wired and tested via the preset picker. Real-device check pending. |
| APP-03 | Wired and tested via the editor rows. Check pending. |
| APP-04 | Wired and tested via the per-band toggle. Check pending. |
| APP-05 | Wired and tested via GraphGeometry and GraphView. Visual check pending. |
| APP-06 | Wired and tested at the model level. Drag gesture check pending. |
| APP-07 | Wired and tested via the pre-gain slider and Auto toggle. Check pending. |
| APP-08 | Wired and tested against FakeDongle. Real Apply pending. |
| APP-09 | Wired and tested via the reload on connect. Check pending. |
| APP-10 | Wired and tested (SampleRate tests, header text). Real value pending. |

## Anti-patterns
None found. No stubs, no debt markers, and no device access from views.

## Human verification required
Run the 11-step script in `03-03-SUMMARY.md` against the real JA11. It writes to the dongle once, through Apply. The backup is already on disk, and the Device menu's Restore Original puts USER1 back.

Open warnings:
- It is not known whether the real device returns `.writeInterrupted` against the watch loop's read. This is noted in the 03-03 summary and is untested because no write was made.
- ROADMAP shows Phase 3 as "In Progress", which fits this status.

## Gaps summary
No code gaps. Completion depends on the human UAT script.

_Verified: 2026-10-11_
_Verifier: Claude (gsd-verifier)_

## Human Verification Results (2026-10-11)

The user ran the app on the real JA11 with the 11-step script from `03-03-SUMMARY.md` available and reported in the main session: "everything works". No individual step results were reported, and no defects or layout complaints were raised. Status changed from `human_needed` to `passed` on this basis.
