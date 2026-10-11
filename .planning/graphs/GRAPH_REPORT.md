# Graph Report - JA11  (2026-10-11)

## Corpus Check
- 79 files · ~140,412 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 1447 nodes · 3544 edges · 65 communities (59 shown, 6 thin omitted)
- Extraction: 80% EXTRACTED · 20% INFERRED · 0% AMBIGUOUS · INFERRED: 722 edges (avg confidence: 0.91)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6fbba7dd`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- SetFrameTests
- EQCurveTests
- FakeDongle
- ApplyTests
- CurveEditor
- BackupStore
- GraphGeometry
- Library the app is built on
- HIDTransport
- .with
- ja11-eq/main.swift
- JA11DeviceTests
- Foundation
- CoreAudioSampleRate
- watch
- Artifacts this phase produces
- JA11Device.swift
- Sendable
- FakeTransport
- AppModel
- NumberField
- FiioFrameTests
- OperationOutcome
- JA11Writer
- JA11Error
- HIDTransportError
- .padded
- Goal Achievement
- Artifacts this phase produces
- Implementation Decisions
- Phase 2 Plan 02: Write Path Failure Handling, Backup and the Write Door Summary
- EQBand
- Phase 2 Plan 04: First Contact With Writes on the Real JA11 Summary
- Artifacts this phase produces
- ja11-probe/main.swift
- PresetSlot
- EQState
- Phase 2 Plan 04: Device Log
- Requirements: JA11 EQ
- Phase 1 Plan 01: Device Link read path Summary
- .emit
- JA11 EQ
- PresetChoice
- .getRequest
- Phase 4: Packaging - Context
- Project State
- Phase 3 Plan 1: App shell, connection model, sample rate Summary
- Phase Details
- CLAUDE.md
- FilterType
- FrameDirection
- ConnectionStatus
- CodingKeys
- Phase 4 Plan 01: Packaging Summary
- .differences
- Needed: records which transport variant works on this Mac and the report layout seen on the device
- Device evidence
- Phase 4: Packaging — Verification
- 02-02-SUMMARY.md
- 02-04-PLAN.md
- 02-02-PLAN.md
- 04-01-PLAN.md
- make-app.sh
- Package.swift

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 74 edges
2. `FiioFrameTests` - 61 edges
3. `Artifacts this phase produces` - 56 edges
4. `FakeDongle` - 55 edges
5. `EQState` - 48 edges
6. `SetFrameTests` - 44 edges
7. `EQCurveTests` - 42 edges
8. `JA11DeviceTests` - 41 edges
9. `CurveEditor` - 40 edges
10. `Artifacts this phase produces` - 40 edges

## Surprising Connections (you probably didn't know these)
- `Build script` --references--> `JA11EQApp`  [INFERRED]
  .planning/phases/04-packaging/04-CONTEXT.md → Sources/JA11EQ/JA11EQApp.swift
- `Deviations from Plan` --references--> `AppModel`  [INFERRED]
  .planning/phases/03-app-ui/03-01-SUMMARY.md → Sources/JA11EQCore/AppModel.swift
- `Evidence run by the verifier` --references--> `AppModel`  [INFERRED]
  .planning/phases/03-app-ui/03-VERIFICATION.md → Sources/JA11EQCore/AppModel.swift
- `Decisions Made` --references--> `JA11Error`  [INFERRED]
  .planning/phases/02-eq-engine-and-write-path/02-01-SUMMARY.md → Sources/JA11Kit/Device/JA11Device.swift
- `STRIDE Threat Register` --references--> `readState()`  [INFERRED]
  .planning/phases/01-device-link/01-02-PLAN.md → Sources/JA11Kit/Device/JA11Device.swift

## Import Cycles
- None detected.

## Communities (65 total, 6 thin omitted)

### Community 0 - "SetFrameTests"
Cohesion: 0.05
Nodes (38): STRIDE Threat Register, Accomplishments, Clamping rules chosen (CONTEXT left NaN and ties open), Decisions Made, Files Created/Modified, How D-01's filter payload was read, Issues Encountered, Next Phase Readiness (+30 more)

### Community 1 - "EQCurveTests"
Cohesion: 0.06
Nodes (11): TDD record, EQCurveTests, Bool, Double, EQCurve, String, Void, EQResponseTests (+3 more)

### Community 2 - "FakeDongle"
Cohesion: 0.06
Nodes (37): Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries, Helpers for later plans (Tests/JA11KitTests), SourceLocation, AppModelConnectionTests, AppModelFixture, NilSampleRates (+29 more)

### Community 3 - "ApplyTests"
Cohesion: 0.08
Nodes (14): ApplyTests, Bool, Double, Duration, JA11Device, UInt8, .sent, Fixture (+6 more)

### Community 4 - "CurveEditor"
Cohesion: 0.09
Nodes (27): Artifacts this phase produces, Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries, Anti-patterns, Evidence run by the verifier, Gaps summary, Human verification required (+19 more)

### Community 5 - "BackupStore"
Cohesion: 0.07
Nodes (34): CustomStringConvertible, Date, Exit statuses, Commits, Deviations from Plan, Human checks (pending, end of phase; these write to the real dongle once, by the user), Known Stubs, Phase 3 Plan 3: Apply, presets, revert, restore Summary (+26 more)

### Community 6 - "GraphGeometry"
Cohesion: 0.08
Nodes (27): Gesture, GraphicsContext, Commits, Deviations from Plan, Known Stubs, Phase 3 Plan 2: Editor and graph Summary, Required statements, Self-Check: PASSED (+19 more)

### Community 7 - "Library the app is built on"
Cohesion: 0.06
Nodes (34): Auto-fixed Issues, Deviations from Plan, Anti-Patterns Found, Behavioral Spot-Checks, Gaps Summary, Goal Achievement, Human Verification Required, Human Verification Results (2026-10-11) (+26 more)

### Community 8 - "HIDTransport"
Cohesion: 0.05
Nodes (36): CFIndex, IOHIDDevice, IOHIDManager, Accomplishments, Decisions Made, Deviations from Plan, Files Created/Modified, Issues Encountered (+28 more)

### Community 9 - ".with"
Cohesion: 0.08
Nodes (13): AppModelOperationTests, OperationFixture, Bool, MainActor, String, URL, AppModelPresetTests, .originalCurve (+5 more)

### Community 10 - "ja11-eq/main.swift"
Cohesion: 0.09
Nodes (36): Error, CLI, CurveFileError, decodingReason(), errorText(), ExitStatus, exitWithResult(), exitWithUsageError() (+28 more)

### Community 11 - "JA11DeviceTests"
Cohesion: 0.19
Nodes (8): Observable Truths, JA11DeviceTests, .stateB, Bool, Duration, T, UInt8, Void

### Community 12 - "Foundation"
Cohesion: 0.15
Nodes (7): AppKit, Foundation, JA11EQCore, JA11Kit, Observation, SwiftUI, Testing

### Community 13 - "CoreAudioSampleRate"
Cohesion: 0.14
Nodes (12): AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock, AudioObjectPropertySelector, CoreAudio, CoreAudioSampleRate, SampleRateFormat, AsyncStream (+4 more)

### Community 14 - "watch"
Cohesion: 0.09
Nodes (27): Accomplishments, Auto-fixed Issues, Decisions Made, Deviations from Plan, Files Created/Modified, Issues Encountered, Next Phase Readiness, Pending human verification (+19 more)

### Community 15 - "Artifacts this phase produces"
Cohesion: 0.15
Nodes (22): CaseIterable, Artifacts this phase produces, Artifacts this phase produces, readFilter(), readFilterCount(), readPreGain(), readSlot(), readState() (+14 more)

### Community 16 - "JA11Device.swift"
Cohesion: 0.19
Nodes (25): CheckedContinuation, apply(), beginWrite(), captureUser1(), discoveryTimedOut(), exchange(), handle(), transport (+17 more)

### Community 17 - "Sendable"
Cohesion: 0.14
Nodes (23): Equatable, Artifacts this phase produces, Decisions Made, Files Created/Modified, Sendable, ApplyReport, .isConfirmed, Kind (+15 more)

### Community 18 - "FakeTransport"
Cohesion: 0.11
Nodes (20): AnyObject, IOKit, IOKit.hid, Files Created, Next Phase Readiness, Artifacts this phase produces, Key Link Verification, Edge and prohibition coverage (spec-less fallback) (+12 more)

### Community 19 - "AppModel"
Cohesion: 0.10
Nodes (20): AppModel, .activePreset, .activePresetTitle, .canApply, .canRestore, .canRevert, .canSelectPreset, .editorEnabled (+12 more)

### Community 20 - "NumberField"
Cohesion: 0.14
Nodes (17): Content, ApplyBarView, .body, .body, BandRow, .band, .body, EditorPanelView (+9 more)

### Community 22 - "OperationOutcome"
Cohesion: 0.10
Nodes (20): Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries, OperationOutcome, confirmed, failed, info, .isSuccess (+12 more)

### Community 23 - "JA11Writer"
Cohesion: 0.22
Nodes (12): Accomplishments, Artifacts this phase produces, Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries, Auto-fixed Issues, Departures from the output contract, Observable Truths (ROADMAP success criteria) (+4 more)

### Community 24 - "JA11Error"
Cohesion: 0.12
Nodes (18): Decisions Made, Apply (APP-08), Claude's Discretion, Device header (APP-01, APP-02, APP-09, APP-10), Editor (APP-03, APP-04), Graph (APP-05, APP-06), Implementation Decisions, Look and behaviour (+10 more)

### Community 25 - "HIDTransportError"
Cohesion: 0.17
Nodes (10): HIDTransportError, accessDenied, .description, notConnected, openFailed, refusedFrame, Int32, String (+2 more)

### Community 26 - ".padded"
Cohesion: 0.14
Nodes (3): Auto-fixed Issues, Deviations from Plan, UInt8

### Community 27 - "Goal Achievement"
Cohesion: 0.12
Nodes (16): 1. Unplug and replug (LINK-02, SC 3), 2. No dongle (D-13), 3. Buttons (LINK-05, SC 4), 4. Permission refusal (LINK-06, SC 5), 5. Flagged prohibitions, Anti-Patterns Found, Behavioral Spot-Checks, Data-Flow Trace (Level 4) (+8 more)

### Community 28 - "Artifacts this phase produces"
Cohesion: 0.24
Nodes (4): Artifacts this phase produces, .body, Error, T

### Community 29 - "Implementation Decisions"
Cohesion: 0.12
Nodes (15): Canonical References, Claude's Discretion, Deferred Ideas, Device and protocol, Evidence, HID transport, Implementation Decisions, Package (+7 more)

### Community 30 - "Phase 2 Plan 02: Write Path Failure Handling, Backup and the Write Door Summary"
Cohesion: 0.12
Nodes (16): Auto-fixed Issues, captureUser1() goes beyond the letter of D-13, Deviations from Plan, Errors the read-back loop treats as "not usable yet", Issues Encountered, Next Phase Readiness, Nothing was sent to the dongle, and the real backup location was not touched, Other differences from the plan's text (+8 more)

### Community 31 - "EQBand"
Cohesion: 0.26
Nodes (6): Codable, Decoder, EQBand, EQCurve, Bool, Double

### Community 32 - "Phase 2 Plan 04: First Contact With Writes on the Real JA11 Summary"
Cohesion: 0.13
Nodes (14): Deviations from Plan, Dongle state at the end, Findings (D-19), Format departures (not device results), Issues Encountered, Known Stubs, Other, Outcome (+6 more)

### Community 33 - "Artifacts this phase produces"
Cohesion: 0.16
Nodes (11): App, Color, Artifacts this phase produces, TDD / RED runs, Scene, ContentView, .header, .statusColor (+3 more)

### Community 34 - "ja11-probe/main.swift"
Cohesion: 0.18
Nodes (11): DispatchSourceSignal, exitCleanlyOnStopSignals(), ExitStatus, inputMonitoringAccess(), makeRawTrace(), Once, printError(), Bool (+3 more)

### Community 35 - "PresetSlot"
Cohesion: 0.14
Nodes (12): Canonical References, Device and protocol, Existing code to extend, Scope, .slot, PresetSlot, bass, classic (+4 more)

### Community 36 - "EQState"
Cohesion: 0.32
Nodes (6): Band, EQState, Double, Int, String, UInt8

### Community 37 - "Phase 2 Plan 04: Device Log"
Cohesion: 0.15
Nodes (12): Baseline, Factory presets after, Factory presets before, Final state, Findings (D-19), Phase 2 Plan 04: Device Log, Step 1: backup, Step 2: preset switch (+4 more)

### Community 38 - "Requirements: JA11 EQ"
Cohesion: 0.15
Nodes (12): App, Convenience, Device Link, EQ Engine and Write Path, Import / Export, Out of Scope, Packaging, Presets (+4 more)

### Community 39 - "Phase 1 Plan 01: Device Link read path Summary"
Cohesion: 0.17
Nodes (11): Accomplishments, Issues Encountered, Performance, Phase 1 Plan 01: Device Link read path Summary, Self-Check: PASSED, Task Commits, The send gate, for Phase 2, Threat Flags (+3 more)

### Community 41 - "JA11 EQ"
Cohesion: 0.17
Nodes (11): Active, Constraints, Context, Core Value, Evolution, JA11 EQ, Key Decisions, Out of Scope (+3 more)

### Community 42 - "PresetChoice"
Cohesion: 0.17
Nodes (11): PresetChoice, bass, classic, custom, .isEditable, off, .slot, .title (+3 more)

### Community 43 - ".getRequest"
Cohesion: 0.20
Nodes (4): Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries, What was sent to the dongle

### Community 44 - "Phase 4: Packaging - Context"
Cohesion: 0.18
Nodes (10): Build script, Canonical References, Claude's Discretion, Deferred Ideas, Implementation Decisions, Phase 4: Packaging - Context, Phase Boundary, README (+2 more)

### Community 45 - "Project State"
Cohesion: 0.18
Nodes (10): Accumulated Context, Blockers/Concerns, Current Position, Decisions, Deferred Items, Pending Todos, Performance Metrics, Project Reference (+2 more)

### Community 46 - "Phase 3 Plan 1: App shell, connection model, sample rate Summary"
Cohesion: 0.20
Nodes (8): Commits, Deviations from Plan, Device safety, Known Stubs, Launch notes, Phase 3 Plan 1: App shell, connection model, sample rate Summary, Self-Check: PASSED, Verification

### Community 47 - "Phase Details"
Cohesion: 0.20
Nodes (9): Overview, Phase 1: Device Link, Phase 2: EQ Engine and Write Path, Phase 3: App UI, Phase 4: Packaging, Phase Details, Phases, Progress (+1 more)

### Community 49 - "CLAUDE.md"
Cohesion: 0.22
Nodes (8): Architecture, Constraints, Conventions, Developer Profile, GSD Workflow Enforcement, Project, Project Skills, Technology Stack

### Community 50 - "FilterType"
Cohesion: 0.22
Nodes (8): Encoder, .codingName, .type, FilterType, .displayName, highShelf, lowShelf, peak

### Community 51 - "FrameDirection"
Cohesion: 0.25
Nodes (8): Result, FrameDirection, received, sent, init(), resumeConnectionWaiters(), Duration, Void

### Community 52 - "ConnectionStatus"
Cohesion: 0.25
Nodes (7): ConnectionStatus, accessRefused, connected, .detail, notConnected, .title, String

### Community 53 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKey, CodingKeys, enabled, frequency, gain, q, type

### Community 54 - "Phase 4 Plan 01: Packaging Summary"
Cohesion: 0.29
Nodes (6): Deviations from Plan, Human checks pending (D-10), Known Stubs, Phase 4 Plan 01: Packaging Summary, Self-Check: PASSED, Tasks

### Community 56 - "Needed: records which transport variant works on this Mac and the report layout seen on the device"
Cohesion: 0.33
Nodes (5): Edge and prohibition coverage (spec-less fallback), Needed: records which transport variant works on this Mac and the report layout seen on the device, Source coverage audit, STRIDE Threat Register, Trust Boundaries

### Community 57 - "Device evidence"
Cohesion: 0.33
Nodes (6): (a) GET replies, (b) Frame form (D-03), (c) Input Monitoring, (d) Report layout, Device evidence, What this means for Phase 2

### Community 58 - "Phase 4: Packaging — Verification"
Cohesion: 0.33
Nodes (5): Not established, Other checks, Phase 4: Packaging — Verification, Requirements, Success criteria

### Community 59 - "02-02-SUMMARY.md"
Cohesion: 0.40
Nodes (4): Actuals (#2632), Dependency graph, Metrics, Tech tracking

### Community 60 - "02-04-PLAN.md"
Cohesion: 0.40
Nodes (4): Artifacts this phase produces, Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries

### Community 61 - "02-02-PLAN.md"
Cohesion: 0.50
Nodes (3): Edge and prohibition coverage (spec-less fallback), STRIDE Threat Register, Trust Boundaries

### Community 62 - "04-01-PLAN.md"
Cohesion: 0.50
Nodes (3): Artifacts this phase produces, STRIDE Threat Register, Trust Boundaries

## Knowledge Gaps
- **340 isolated node(s):** `PackageDescription`, `.statusColor`, `.band`, `Observation`, `.activePresetTitle` (+335 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 471 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Artifacts this phase produces` connect `Artifacts this phase produces` to `SetFrameTests`, `EQCurveTests`, `FakeDongle`, `ApplyTests`, `BackupStore`, `GraphGeometry`, `Library the app is built on`, `HIDTransport`, `JA11Device.swift`, `Sendable`, `FakeTransport`, `JA11Writer`, `JA11Error`, `HIDTransportError`, `EQBand`, `PresetSlot`, `EQState`, `FilterType`, `.differences`?**
  _High betweenness centrality (0.171) - this node is a cross-community bridge._
- **Why does `AppModel` connect `AppModel` to `Artifacts this phase produces`, `FakeDongle`, `CurveEditor`, `BackupStore`, `GraphGeometry`, `EQState`, `.with`, `PresetChoice`, `Foundation`, `Phase 3 Plan 1: App shell, connection model, sample rate Summary`, `NumberField`, `ConnectionStatus`, `OperationOutcome`, `JA11Writer`, `Artifacts this phase produces`?**
  _High betweenness centrality (0.129) - this node is a cross-community bridge._
- **Why does `JA11Writer` connect `JA11Writer` to `ApplyTests`, `BackupStore`, `Library the app is built on`, `HIDTransport`, `.with`, `Artifacts this phase produces`, `Phase Details`, `Sendable`, `AppModel`, `OperationOutcome`, `02-04-PLAN.md`, `02-02-PLAN.md`, `Phase 2 Plan 02: Write Path Failure Handling, Backup and the Write Door Summary`?**
  _High betweenness centrality (0.090) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `AppModel` (e.g. with `03-01-PLAN.md` and `Artifacts this phase produces`) actually correct?**
  _`AppModel` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `FiioFrameTests` (e.g. with `Artifacts this phase produces` and `TDD (Task 2)`) actually correct?**
  _`FiioFrameTests` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 55 inferred relationships involving `Artifacts this phase produces` (e.g. with `.frequency()` and `.gain()`) actually correct?**
  _`Artifacts this phase produces` has 55 INFERRED edges - model-reasoned connections that need verification._
- **Are the 24 inferred relationships involving `FakeDongle` (e.g. with `Artifacts this phase produces` and `Nothing was sent to the real dongle`) actually correct?**
  _`FakeDongle` has 24 INFERRED edges - model-reasoned connections that need verification._