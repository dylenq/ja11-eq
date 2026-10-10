---
phase: 02-eq-engine-and-write-path
plan: 01
subsystem: write-path
tags: [swift, swiftpm, hid, swift-testing, codable, biquad, rbj-cookbook, dsp]

# Dependency graph
requires:
  - phase: 01-device-link
    provides: JA11Kit read path (FiioFrame GET codec, HIDTransport behind ReportTransport, JA11Device actor, EQ model), FakeTransport, and the device facts (padded 20-byte form, 21-byte replies, current USER1 contents)
provides:
  - JA11WriteCommand (five commands) and JA11Limits wire-unit helpers that clamp before encoding
  - SET frame builders (setPreGain, setFilterCount, setFilter, selectSlot, saveToUser1) and the isSetRequest / isPermittedFrame allow-list
  - HIDTransport.send gated by FiioFrame.isPermittedFrame
  - EQBand and EQCurve (Codable, clamped(), deviceState(), init?(state:)) and EQState.differences(from:)
  - Biquad (RBJ peaking, low shelf, high shelf), EQCurve.bandResponse / response / logGrid / autoPreGain
  - JA11Device.apply(_:) (internal) with ApplyReport, LinkEvent, JA11Error.writeInterrupted and .noReadBack
  - FakeDongle, an in-memory JA11 for tests
affects: [02-02 failure handling and backup, 02-03 ja11-eq command, 02-04 first contact with writes, phase-3-app-ui]

# Actuals (#2632)
actuals:
  tokens: 23380
  tasks: 3
  commits: 5
plan_head_before: 010a95dba95091db9a577df987f271227e5d5539
plan_head_after: 38b41128144dee641d216995c9b398d4e42e9786

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One clamp-and-round helper per wire unit on JA11Limits; the curve model, the frame builders and nothing else convert to wire units"
    - "Three layers refuse an out-of-range value: EQCurve.clamped(), the builders, and the gate"
    - "Write frames come only from FiioFrame builders; the builders are internal and the save builder takes no slot"
    - "FakeDongle: a FakeTransport responder that stores SET frames and answers GET frames from a working state"
    - "Read-back comparison scales and rounds both sides, never clamps the device's values"

key-files:
  created:
    - Sources/JA11Kit/Model/EQCurve.swift
    - Sources/JA11Kit/DSP/EQResponse.swift
    - Tests/JA11KitTests/FakeDongle.swift
    - Tests/JA11KitTests/ApplyTests.swift
    - Tests/JA11KitTests/SetFrameTests.swift
    - Tests/JA11KitTests/EQCurveTests.swift
    - Tests/JA11KitTests/EQResponseTests.swift
  modified:
    - Sources/JA11Kit/Protocol/JA11Commands.swift
    - Sources/JA11Kit/Protocol/FiioFrame.swift
    - Sources/JA11Kit/HID/HIDTransport.swift
    - Sources/JA11Kit/Device/JA11Device.swift

key-decisions:
  - "The transport's gate is FiioFrame.isPermittedFrame: the eight GET shapes as before, plus 20-byte SET frames for the five write commands with values inside the device limits; a save is accepted for slot 3 only"
  - "D-01's filter payload is read as 8 data bytes (index, gain, frequency, Q, type) followed by the 00 EE terminator; the PROJECT.md reference frame is pinned byte for byte"
  - "Clamping replaces NaN first (gain and pre-gain by 0.0, Q by 0.1, frequency by 20 Hz), then clamps, then rounds to the wire step with ties away from zero; an infinity ends on the limit on its side"
  - "The read-back comparison rounds to wire units without clamping, so a device value outside the device limits is always a difference; a non-finite value on either side is a difference"
  - "Biquad.magnitudeDB evaluates the plan's squared-magnitude sum through sin^2(w/2) instead of cos(w) and cos(2w): same value, without the cancellation that cost about seven digits at low frequencies"
  - "Decoding a curve does not clamp; a band without the enabled key decodes as enabled; clamped() is what the write path applies"

patterns-established:
  - "Write-path tests run on FakeDongle; no test creates an HIDTransport"
  - "Gate tests build a refused frame from a builder's output with one byte changed"

requirements-completed: ["WRITE-01", "WRITE-02", "WRITE-04", "WRITE-05", "WRITE-09", "WRITE-10"]

coverage:
  - id: D1
    description: "A curve travels the whole write path on an in-memory dongle: clamping, the nine pinned SET frames in order, save to slot 3, select slot 3, and a read-back that matches what was sent"
    requirement: "WRITE-01"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#applyWithUser1ActiveSendsTheNinePinnedFramesAndIsConfirmedByReadBack"
        status: pass
    human_judgment: false
  - id: D2
    description: "An apply is reported as confirmed only when the state read back equals what was sent; ignored writes and out-of-range read-back values are reported as differences"
    requirement: "WRITE-02"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#aDongleThatIgnoresWritesIsReportedAsAMismatchNotAsConfirmed"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/EQCurveTests.swift#aGainReadBackOutsideTheDeviceLimitsIsADifference"
        status: pass
    human_judgment: false
  - id: D3
    description: "No value or save frame is sent while a factory slot is active: the apply selects USER1 and confirms it first, and ends with writeInterrupted when the switch is not confirmed"
    requirement: "WRITE-04"
    verification:
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#applyFromAFactorySlotSelectsUser1AndConfirmsItBeforeAnyValueIsSent"
        status: pass
      - kind: integration
        ref: "Tests/JA11KitTests/ApplyTests.swift#anUnconfirmedSwitchToUser1EndsTheApplyBeforeAnyValueOrSaveIsSent"
        status: pass
    human_judgment: false
  - id: D4
    description: "The send gate accepts the GET shapes and SET frames for the five write commands only, and refuses a save to any slot but 3, out-of-range slots, indices, counts and values, other command bytes, other lengths and a non-zero byte before EE"
    requirement: "WRITE-04"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/SetFrameTests.swift#gateRefusesASaveToAnySlotButThree"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/SetFrameTests.swift#gateAcceptsNoCommandByteOutsideTheFiveWriteCommands"
        status: pass
      - kind: other
        ref: "grep -q isPermittedFrame Sources/JA11Kit/HID/HIDTransport.swift; one IOHIDDeviceSetReport call site under Sources"
        status: pass
    human_judgment: false
  - id: D5
    description: "SET frames encode byte for byte as D-01 states, including the PROJECT.md reference filter frame and two's-complement negative gain and pre-gain"
    requirement: "WRITE-01"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/SetFrameTests.swift#filterBuilderGivesTheProjectReferenceFrameByteForByte"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/SetFrameTests.swift#preGainEncodesAsTwosComplementBigEndian"
        status: pass
    human_judgment: false
  - id: D6
    description: "EQCurve.clamped() forces gain, Q, frequency and pre-gain into the device limits at wire resolution, pads to five bands with neutral ones, keeps array order and the first five bands; a disabled band is sent with 0.0 dB"
    requirement: "WRITE-05"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/EQCurveTests.swift (34 tests: clamping, rounding, NaN, padding, ordering, JSON)"
        status: pass
    human_judgment: false
  - id: D7
    description: "The combined response of peak, low-shelf and high-shelf bands matches known values; response(at:) includes pre-gain and bandResponse(at:) leaves it out"
    requirement: "WRITE-09"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/EQResponseTests.swift#aLowShelfIsHalfItsGainAtTheCornerAndFullGainWellBelow"
        status: pass
      - kind: unit
        ref: "Tests/JA11KitTests/EQResponseTests.swift#aPlus6PeakReadsPlus6AtItsCentreAndFallsAwayOnBothSides"
        status: pass
    human_judgment: false
  - id: D8
    description: "autoPreGain() offsets the largest boost, rounded down to 0.1 dB, within -12...0 dB"
    requirement: "WRITE-10"
    verification:
      - kind: unit
        ref: "Tests/JA11KitTests/EQResponseTests.swift#autoPreGainRoundsTowardMoreAttenuation"
        status: pass
    human_judgment: false
  - id: D9
    description: "The SET frames, as encoded here, are accepted by the real JA11 and the saved curve persists on the device"
    requirement: "WRITE-01"
    verification: []
    human_judgment: true
    rationale: "Nothing was sent to the real dongle in this plan. First contact with writes belongs to plan 02-04; whether the device accepts 00 before EE on write frames is a flagged assumption (D-04)."

# Metrics
duration: 9min
completed: 2026-10-10
status: complete
---

# Phase 2 Plan 01: EQ Engine and Write Path Core Summary

**Curve model with clamping, byte-pinned SET-frame encoding behind an allow-list send gate, an apply sequence confirmed by read-back on an in-memory dongle, and RBJ response math with auto pre-gain — all proven by `swift test` with nothing sent to the real JA11.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-10-10T15:27:23Z
- **Completed:** 2026-10-10T15:36:37Z
- **Tasks:** 3
- **Files modified:** 11 (7 created, 4 modified)
- **Tests:** 177 in 7 suites, all passing (Phase 1 ended at 83 in 3)

## Accomplishments

- A curve built in a test goes through `clamped()`, the SET builders and `JA11Device.apply(_:)` to an in-memory dongle and comes back confirmed by a read-back. The write frames sent are exactly the nine pinned frames, in the pinned order.
- The transport's send gate is now an explicit allow-list (see below) instead of GET-only.
- The apply never sends a value or a save while a factory slot is active: it reads the slot, switches to USER1 if needed, and reads the slot again before anything else goes out.
- A read-back that differs from what was sent is reported as a list of differences, never as confirmed — including device values outside the device limits.
- Response math for peak, low-shelf and high-shelf bands and auto pre-gain are in place for the Phase 3 graph.

## Nothing was sent to the real dongle

No SET frame reached the JA11 while this plan was executed, and no GET frame either: `ja11-probe` was not run. No executable that writes exists yet. Every test runs on `FakeTransport` / `FakeDongle`; no test creates an `HIDTransport`. `Sources/ja11-probe/main.swift` and `Package.swift` are byte for byte what they were at `cbbf4c3`.

## The send gate: `FiioFrame.isPermittedFrame`

`HIDTransport.send` now refuses any payload for which `FiioFrame.isPermittedFrame` is false, before IOKit is touched. It is `isGetRequest || isSetRequest`:

- **Accepted, read:** the eight Phase 1 GET shapes, in both forms, unchanged.
- **Accepted, write:** a payload of exactly 20 bytes that starts `AA 0A 00 00`, carries one of the five write commands (filter, preset slot, pre-gain, filter count, save) with exactly that command's data length, has `00 EE` straight after the data and zero bytes from there on.
- **Refused:**
  - a save for any slot but 3
  - a preset switch outside slots 0–4
  - a filter index outside 0–4, a filter type above 2
  - a filter count above 5
  - a filter gain or pre-gain outside −120…120 tenths, a frequency outside 20…20000 Hz, a Q outside 10…1000 hundredths
  - any other command byte (tested over all 256 values)
  - a length byte that is not the command's own
  - any length other than 20 bytes, including the unpadded SET form
  - a non-zero padding byte, a non-zero byte before `EE` (D-04), a missing `EE`
  - any other header, including a save dressed as a GET request

There is one `IOHIDDeviceSetReport` call site under `Sources/`. The builders are internal; `saveToUser1()` takes no slot, so the library has no way to build a save for another slot (D-11). No constant exists for the reset, firmware, device-name or chip-vendor bytes (D-03).

## How D-01's filter payload was read

The filter frame carries **8 data bytes**: index, gain (2, signed big-endian, dB × 10), frequency (2, unsigned, Hz), Q (2, unsigned, × 100), type. The `0x00` that D-01 lists after the type is the first byte of the `00 EE` terminator, as the reference frame shows. That frame is pinned byte for byte in `SetFrameTests` and `ApplyTests`:

`AA 0A 00 00 15 08 00 00 3C 00 64 00 46 01 00 EE` followed by four zero bytes.

Negative values are two's complement, high byte first: pre-gain −6.0 dB is `FF C4`, filter gain −3.0 dB is `FF E2`, −0.1 dB is `FF FF`.

## Clamping rules chosen (CONTEXT left NaN and ties open)

Every value passes one helper on `JA11Limits` (`gainTenths`, `preGainTenths`, `qHundredths`, `hertz`) that works in this order:

1. **NaN is replaced:** gain and pre-gain by 0.0 dB, Q by 0.1, frequency by 20 Hz (the neutral value where there is one, the lower limit otherwise).
2. **Clamp** to the device limit. Positive infinity ends on the upper limit, negative infinity on the lower.
3. **Scale and round** to the wire step with ties away from zero (`.toNearestOrAwayFromZero`): 0.25 dB becomes 0.3, −0.25 becomes −0.3, Q 0.125 becomes 0.13, 100.5 Hz becomes 101.

A value on a limit is kept; a value one wire step outside moves onto it. `clamped()` applied twice equals `clamped()` applied once.

## Task Commits

1. **Task 1 (tracer): end-to-end apply on an in-memory dongle** — `2f76929` (feat)
2. **Task 2: gate refusals, model clamps, reference frames** — `5769107` (test, RED), `49aa8f5` (feat, GREEN)
3. **Task 3: frequency response and auto pre-gain** — `4d5d24e` (test, RED), `38b4112` (feat, GREEN)

Tracer feedback gate: interactive run, `human_verify_mode: end-of-phase`, automated-only verify — the tracer's verify was re-run and passed before Tasks 2 and 3 began.

## TDD record

- **Task 2 RED:** 158 tests ran, 3 failed on assertions (`aBandWithoutTheEnabledKeyDecodesAsEnabled`, `decodingDoesNotClamp`, `malformedCurvesFailToDecode`), all for one reason: synthesized decoding required the `enabled` key. **GREEN:** hand-written `EQBand.init(from:)` with `decodeIfPresent`. The gate and clamp tests passed on first run, as the plan expected ("most of the behaviour exists from Task 1").
- **Task 3 RED:** the signatures with stub bodies; 15 of 19 `EQResponseTests` failed on assertions. **GREEN:** the RBJ biquads, the grid and auto pre-gain.
- No refactor commits.
- `gsd-tools check tdd-red-evidence` was tried for Task 2 and could not classify the run: it parses TAP or JUnit output, and Swift Testing's console output is neither. The RED runs are recorded here instead. The plan is `type: execute`, so the plan-level TDD gate does not apply.

## Files Created/Modified

- `Sources/JA11Kit/Protocol/JA11Commands.swift` — `JA11WriteCommand`, wire-unit helpers on `JA11Limits`
- `Sources/JA11Kit/Protocol/FiioFrame.swift` — `setHeader`, the five SET builders, `isSetRequest`, `isPermittedFrame`
- `Sources/JA11Kit/HID/HIDTransport.swift` — gate swapped to `isPermittedFrame`, `refusedFrame` wording
- `Sources/JA11Kit/Model/EQCurve.swift` — `EQBand`, `EQCurve`, `FilterType` Codable, `EQState.differences(from:)`
- `Sources/JA11Kit/DSP/EQResponse.swift` — `Biquad`, response, grid, auto pre-gain
- `Sources/JA11Kit/Device/JA11Device.swift` — `apply(_:)`, `ApplyReport`, `LinkEvent`, two error cases, three init parameters
- `Tests/JA11KitTests/FakeDongle.swift` — in-memory JA11
- `Tests/JA11KitTests/ApplyTests.swift` (4 tests), `SetFrameTests.swift` (37), `EQCurveTests.swift` (34), `EQResponseTests.swift` (19)

## Decisions Made

See `key-decisions` in the frontmatter. In addition:

- The three new `JA11Device.init` parameters sit before `trace`, so every existing call site compiles unchanged.
- `apply(_:)` after the save: each attempt until the reconnect timeout sends select-slot-3 and reads the whole state; only `JA11Error` failures lead to another attempt, with a pause of at least 10 ms. The save and the value frames are never sent a second time.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Magnitude formula lost precision at low frequencies**
- **Found during:** Task 3 (GREEN)
- **Issue:** The squared-magnitude sum written with `cos(w)` and `cos(2w)`, as the plan spells it, subtracts nearly equal numbers at low frequencies. A −6 dB low shelf read −3.0000016 dB at its 100 Hz corner, outside the 1e-6 tolerance; the +6 dB case of the plan's own truth passed only by a small margin.
- **Fix:** `Biquad.magnitudeDB` evaluates the same sum in terms of `sin²(w/2)`. Algebraically identical, no complex numbers, error now around 1e-10 dB.
- **Files modified:** `Sources/JA11Kit/DSP/EQResponse.swift`
- **Verification:** `EQResponseTests` 19 of 19 pass, including the cut-shelf corner at 1e-6
- **Committed in:** `38b4112`

**2. [Rule 2 - Missing critical] Read-back comparison also checks each filter's index**
- **Found during:** Task 1
- **Issue:** The plan lists type, frequency, gain and Q per filter. A read-back whose filter reports another index than its position would have compared as equal.
- **Fix:** `differences(from:)` adds `filter N index: sent N, read M` when the indices differ. The lines and wording the plan fixes are unchanged.
- **Files modified:** `Sources/JA11Kit/Model/EQCurve.swift`
- **Committed in:** `2f76929`

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Neither changes an interface or a pinned frame. No scope creep.

## Issues Encountered

- Two test-file compile errors while writing Task 2's tests (a key-path closure and a `try` inside `#expect`), fixed before the RED run.

## Verification

- `swift build` exits 0
- `swift test`: `Test run with 177 tests in 7 suites passed`, Phase 1 suites included
- `git diff --quiet cbbf4c3 -- Sources/ja11-probe/main.swift Package.swift` succeeds
- No `0x1B|0x1C|0x30|0x4B|0x54` and no `SeizeDevice` under `Sources/`; `0x19` once, `0x0B` once
- `IOHIDDeviceSetReport(` appears once under `Sources/`
- Every task's acceptance criteria were run and passed

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for plan 02-02: `apply(_:)` is internal and handles the uninterrupted case; a dropped link, a busy device and an interrupted sequence are to be added to the same function, and the public door, backup and restore go in front of it.
- `requirements-completed` copies the plan's list. WRITE-05, WRITE-09 and WRITE-10 are complete. WRITE-01, WRITE-02 and WRITE-04 are proven on the in-memory dongle only and still depend on plans 02-02 and 02-04.
- Still open, for plan 02-04 on the device: whether the JA11 accepts write frames with `00` before `EE`; whether a read about 1.5 s after the save shows the saved values; whether the save reaches non-volatile memory.

## Self-Check: PASSED

- All 7 created files exist on disk.
- Commits `2f76929`, `5769107`, `49aa8f5`, `4d5d24e`, `38b4112` are in `git log`.
- `commits: 5` is measured: `git rev-list --count 010a95d..38b4112`.

---
*Phase: 02-eq-engine-and-write-path*
*Completed: 2026-10-10*
