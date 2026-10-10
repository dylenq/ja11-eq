---
phase: 03-app-ui
plan: 01
subsystem: app-shell
tags: [swiftui, observation, coreaudio, hid]
requires: [JA11Kit watch()/readState]
provides: [JA11EQCore library, JA11EQ executable, AppModel, ConnectionStatus, PresetChoice, SampleRateFormat, CoreAudioSampleRate, test helpers]
affects: [03-02, 03-03]
tech-stack:
  added: []
  patterns: [MainActor Observable model over actor device, AsyncStream listeners]
key-files:
  created:
    - Sources/JA11EQCore/DeviceStatus.swift
    - Sources/JA11EQCore/AppModel.swift
    - Sources/JA11EQCore/SampleRate.swift
    - Sources/JA11EQ/JA11EQApp.swift
    - Sources/JA11EQ/ContentView.swift
    - Tests/JA11KitTests/AppModelConnectionTests.swift
    - Tests/JA11KitTests/SampleRateTests.swift
  modified: [Package.swift]
decisions:
  - "AppModel.handle(_:) is the single mutation point for link state; tests drive it through the FakeDongle transport"
  - "Sample rate text computed with integer tenths of kHz, no locale"
metrics:
  tasks: 3
  tests: 239 passing (17 new)
status: complete
actuals:
  tokens: 20000
  tasks: 3
  commits: 3
plan_head_before: 1fff2d9
plan_head_after: d0a6e6bcbd40b29872dd93261667552340a4058f
---

# Phase 3 Plan 1: App shell, connection model, sample rate Summary

A SwiftPM `JA11EQ` executable over a `JA11EQCore` logic library whose `AppModel` follows `JA11Device.watch()` and CoreAudio, showing connection, active preset and output sample rate in a window header.

## Commits
- 14414d1 feat: package targets, AppModel, ContentView, app shell, SampleRate.swift
- 5d2702e test: AppModelConnectionTests (11 tests)
- d0a6e6b test: SampleRateTests (6 tests)

## Launch notes
- Run `"$(swift build --show-bin-path)/JA11EQ"`. Because it is not an `.app` bundle, `JA11EQApp.init()` calls `NSApplication.shared.setActivationPolicy(.regular)` and the content's `.task` calls `NSApp.activate(ignoringOtherApps: true)` before `model.start()`. Without that the window opens behind the terminal.
- Launch check: process still running 5 s after start with the real dongle plugged in; killed afterward, no `JA11EQ` process left.
- Input Monitoring is granted to the launching terminal app (per the transport's error text).

## Helpers for later plans (Tests/JA11KitTests)
- `AppModelFixture.make(dongle:connected:sampleRates:)` (in AppModelConnectionTests.swift): builds a started AppModel; `connected: true` emits `.connected` after start.
- `waitUntil(timeout:_:_:)`: main-actor 2 ms poll, records an Issue on timeout.
- `NilSampleRates` (yields nil) and `FakeSampleRates` (test feeds with `feed(_:)`).

## Deviations from Plan
**1. [Process] TDD ordering not followed strictly.** Task 1's AppModel was written with the full `handle(_:)` mapping (including readFailed, statusLog, stateLoadCount) and Task 3's `SampleRate.swift` landed in the Task 1 commit because `AppModel` references it. Tests were written afterward and passed first run; no separate RED runs were observed (`check tdd-red-evidence` also cannot parse Swift Testing output). Task 1/2/3 commits are therefore not perfectly split by task.
No other deviations.

## Verification
- `swift build` clean; `swift test` 239/239; connection tests passed 3 consecutive runs.
- Gates: no `.package(`, no SwiftUI in JA11EQCore, no JA11Writer/FiioFrame in app sources, no `AudioObjectSetPropertyData`, JA11Kit/probe/ja11-eq untouched.
- On-screen look of the header is a human check in plan 03-03.

## Device safety
Nothing was written to the dongle. Tests use FakeDongle only (a test asserts only BB 0B read frames are sent on load); the app launch performed reads only. No backup store was touched.

## Known Stubs
None. (ContentView's read-only filter list is an intentional tracer view, replaced by the editor in 03-02.)

## Self-Check: PASSED
All created files present; commits 14414d1, 5d2702e, d0a6e6b exist.
