---
phase: 03-app-ui
plan: 02
subsystem: editor
tags: [swiftui, canvas, editor-model, graph-geometry]
requires: [03-01 AppModel, JA11Kit EQCurve/EQResponse]
provides: [CurveEditor, GraphGeometry, GraphPoint, AppModel.editor, editorEnabled, editorNote, EditorPanelView, GraphView]
affects: [03-03]
tech-stack:
  added: []
  patterns: [value-type editor with clamp-on-every-edit, window-free geometry type]
key-files:
  created:
    - Sources/JA11EQCore/CurveEditor.swift
    - Sources/JA11EQCore/GraphGeometry.swift
    - Sources/JA11EQ/EditorPanelView.swift
    - Sources/JA11EQ/GraphView.swift
    - Tests/JA11KitTests/CurveEditorTests.swift
    - Tests/JA11KitTests/GraphGeometryTests.swift
    - Tests/JA11KitTests/AppModelEditorTests.swift
  modified:
    - Sources/JA11EQCore/AppModel.swift
    - Sources/JA11EQ/ContentView.swift
decisions:
  - "Clipping marker threshold is 0.05 dB, not strictly 0: a boost's tails are positive everywhere"
  - "A dirty editor is replaced only after a .disconnected has been seen since the last load"
metrics:
  tasks: 3
  tests: 276 passing (37 new)
status: complete
actuals:
  tokens: 30000
  tasks: 3
  commits: 3
plan_head_before: 62ea6eb06e569a56258881435ed0469addc1bc50
plan_head_after: 56434b1dbc4e1b592d8fdc8c84ac735114b2591d
---

# Phase 3 Plan 2: Editor and graph Summary

Tested `CurveEditor` and `GraphGeometry` value types, loaded from the DAC state by `AppModel`, with SwiftUI band rows, pre-gain/Auto control and a Canvas response graph with draggable numbered handles.

## Commits
- c5a53b4 feat: CurveEditor, AppModel editor loading, CurveEditorTests + AppModelEditorTests
- 591ee69 feat: GraphGeometry + GraphGeometryTests
- 56434b1 feat: EditorPanelView, GraphView, ContentView

## Required statements
- **Q from the graph:** Option-drag. Option is read from `NSEvent.modifierFlags` at drag start; vertical movement calls `scaleQ(band:by:)` with factor `exp(-dy * 0.01)` per change (drag up raises Q).
- **Hit test:** radius 12 pt; only enabled bands; nearest handle wins; on equal distance the highest index wins (drawn on top).
- **Nothing was written to the dongle.** No write path exists in the app sources (no JA11Writer/FiioFrame/JA11Device in views); tests use FakeDongle and assert `writeFrames.isEmpty`; the launch check performed reads only. No backup store was touched.

## TDD / RED runs
- Task 1: CurveEditorTests first run failed to compile (`cannot find type 'CurveEditor'`), then implemented. One test failure afterwards, see deviation 1.
- Task 2: after implementation, first run failed on 3 assertions (see deviations 2-3); fixed.
- AppModelEditorTests written before the AppModel change but the file was added in the same step as the implementation, so no separate RED run was recorded for it.
- `check tdd-red-evidence` skipped (cannot parse Swift Testing output).

## Deviations from Plan
**1. [Rule 1 - Test expectation] Q 1.005 does not give 1.01.** `1.005 * 100` is 100.49999999999999 in floating point, so existing `JA11Limits.qHundredths` yields 1.00. JA11Kit is out of scope; the test uses 1.006 -> 1.01 and 1.004 -> 1.0 instead.
**2. [Rule 1 - Bug] `frequency(forFraction: 1)` returned 19999.999999999996** (exp/log round trip); fraction >= 1 now returns exactly 20000.
**3. [Rule 1 - Bug] Clipping ranges "strictly above 0 dB" marked the entire axis** for any boost, since a peak filter's tails are always slightly positive. Threshold is now 0.05 dB (below the device's 0.1 dB resolution). Tests for flat, auto-pre-gain and -12 dB pre-gain still give no ranges; two separated narrow boosts give two ranges.
**4. [Test geometry]** the plan's near-handle hit test needed handles within 12 pt; the test uses a 0.2 dB (2 pt) gap since the axis is 10 pt per dB at 300 pt height.
**5. [Process]** `editorNote` additionally requires a non-empty editor so an unshowable state shows `readFailure` and no note.

## Verification
- `swift build` clean; `swift test` 276 passing in 14 suites; app still running 5 s after launch, killed afterwards, no JA11EQ process left.
- Gates: no JA11Writer/FiioFrame/JA11Device in `Sources/JA11EQ`; no `.sort` in CurveEditor; `Package.swift` untouched.
- On-screen look, drag feel and Option-drag are human checks in plan 03-03.

## Known Stubs
None.

## Self-Check: PASSED
All created files present; commits c5a53b4, 591ee69, 56434b1 exist.
