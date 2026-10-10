---
gsd_state_version: "1.0"
current_phase: 01
current_phase_name: Device Link
status: executing
stopped_at: Completed 01-01-PLAN.md
last_updated: "2026-10-10T10:26:57.760Z"
last_activity: 2026-10-10
last_activity_desc: Phase 01 execution started
state_head: b836eba877296149e7a67f03153644fc9a7a80f6
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 2
  completed_plans: 1
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-10)

**Core value:** Edit an EQ curve on the Mac, press Apply, and the JA11 plays with that curve — reliably, and without ever damaging the dongle's factory presets.
**Current focus:** Phase 01 — Device Link

## Current Position

Phase: 01 (Device Link) — EXECUTING
Plan: 2 of 2
Status: Ready to execute
Last activity: 2026-10-10 — Phase 01 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: - min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 14 min | 2 tasks | 9 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Four phases, each ending in a check on the real dongle: Device Link → EQ Engine and Write Path → App UI → Packaging
- [Roadmap]: Phase 1 ships only the read-only probe; the first write to the DAC happens in Phase 2
- [Project]: Only USER1 (slot 3) is ever written, and the original USER1 is saved before the first write
- [Project]: Swift package (`JA11Kit` library, `ja11-probe` CLI, app), macOS 14+, zero third-party dependencies
- [Phase 01]: HIDTransport opens the manager with IOHIDManagerOpen (non-exclusive, before activation) as well as the device: without it the manager-level input-report callback never fired on this Mac
- [Phase 01]: The JA11 answers GET requests in the padded 20-byte form; input reports are 21 bytes with a leading report-ID byte (headerOffset 1); no Input Monitoring refusal was seen
- [Phase 01]: The transport send gate accepts only the eight D-03 reference request shapes (exact data length per command); Phase 2 must replace the gate deliberately to add writes
- [Phase 01]: readFilter(index:) traps outside 0..<5 rather than sending a request for a filter the device does not have; a filter count above 5 ends readState before any filter request

### Pending Todos

None yet.

### Blockers/Concerns

No blockers. Open questions carried from PROJECT.md, to settle on the real device:

- [Phase 1]: Does macOS need Input Monitoring to open the HID device (its top-level usage is Consumer Control)? Decides what LINK-06 tells the user.
- [Phase 2]: Pre-gain scale (× 10 assumed) — verify by read-back and by ear.
- [Phase 2]: The dongle may drop off USB after a save (`disconnectOnSave`) — WRITE-07 covers recovery.
- [Phase 2]: Is the on-board EQ active at 352.8 kHz, and is a filter write audible before the save? Answers feed v2 CONV-04 and CONV-02.
- [Phase 2]: The WRITE-04 check assumes a factory preset's filters can be read by selecting its slot — unverified on the device.
- [Phase 2]: Needs a command-line way to write that leaves a plain `ja11-probe` run read-only (LINK-04) — decide in planning.
- [Phase 2]: Replies carry an undocumented, varying byte before EE (bd, 94, f1, ...); GET requests carry 00 there and are answered. Check whether a SET frame needs that byte before the first write (see 01-01-SUMMARY).

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-10T10:26:32.951Z
Stopped at: Completed 01-01-PLAN.md
Resume file: None
