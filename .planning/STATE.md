---
gsd_state_version: "1.0"
current_phase: 02
current_phase_name: EQ Engine and Write Path
status: executing
stopped_at: Completed 02-03-PLAN.md
last_updated: "2026-10-10T15:55:29.126Z"
last_activity: 2026-10-10
last_activity_desc: Phase 02 execution started
state_head: 93ee15a585fad07bc830000725077136b94b7c64
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 6
  completed_plans: 5
  percent: 25
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-10)

**Core value:** Edit an EQ curve on the Mac, press Apply, and the JA11 plays with that curve — reliably, and without ever damaging the dongle's factory presets.
**Current focus:** Phase 02 — EQ Engine and Write Path

## Current Position

Phase: 02 (EQ Engine and Write Path) — EXECUTING
Plan: 4 of 4
Status: Ready to execute
Last activity: 2026-10-10 — Phase 02 execution started

Progress: [███░░░░░░░] 25%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: - min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 14 min | 2 tasks | 9 files |
| Phase 01 P02 | 6 min | 3 tasks | 4 files |
| Phase 02 P01 | 9 min | 3 tasks | 11 files |
| Phase 02 P02 | 9 min | 2 tasks | 9 files |
| Phase 02 P03 | 3 min | 2 tasks | 2 files |

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
- [Phase 01]: readState ends with disconnected when the dongle was replugged during the read, so one state never combines values from two connections
- [Phase 01]: JA11Device.watch() supports one watcher and runs a fresh read on every connect; ja11-probe exit statuses are 0 state printed, 1 no JA11, 2 usage error, 3 access refused, 4 read failed
- [Phase 01]: On the real JA11, Input Monitoring status was unknown while open and reads succeeded: no grant was needed for the probe as launched from Claude Code. A refusal was never seen; unplug/replug, buttons and the permission check await human verification
- [Phase 02]: The transport send gate is FiioFrame.isPermittedFrame: GET shapes as before plus 20-byte SET frames for the five write commands with values inside device limits; a save is accepted for slot 3 only
- [Phase 02]: D-01 filter payload is 8 data bytes followed by the 00 EE terminator; the PROJECT.md reference frame is pinned byte for byte
- [Phase 02]: Clamping replaces NaN (gain and pre-gain 0.0, Q 0.1, frequency 20 Hz), clamps, then rounds to the wire step with ties away from zero
- [Phase 02]: Read-back comparison rounds to wire units without clamping, so a device value outside the limits is always a difference
- [Phase 02]: Biquad magnitude is evaluated through sin^2(w/2) to avoid cancellation at low frequencies; response math runs at a nominal 96 kHz
- [Phase 02]: Write pauses and timeouts: framePause 100 ms, saveSettle 1500 ms, reconnectTimeout 10 s, read-back retry wait 200 ms; before the save any failure ends the apply with writeInterrupted and no save, after it only the select frame may repeat
- [Phase 02]: After a save, disconnected, notConnected, noReply, busy, transport(notConnected) and transport(sendFailed) mean not usable yet and lead to another read-back round; any other error ends the apply
- [Phase 02]: captureUser1 re-selects the slot that was active and requires the read-back to match, beyond the letter of D-13; a backup from USER1 sends no write frame
- [Phase 02]: The backup file is written once through a temporary file and link(2); nothing in BackupStore replaces, changes or deletes an existing file, and an unreadable file stops every write
- [Phase 02]: JA11Writer is the only public way to write; apply, applyTestCurve and selectSlot take the backup first, and an unconfirmed restore sends nothing further
- [Phase 02]: ja11-eq checks arguments, the curve file and the backup file before a transport exists; an unreadable backup or a restore without one exits 6 without opening the device
- [Phase 02]: ja11-eq exit statuses: 0 confirmed, 1 no JA11, 2 usage error or unreadable curve file, 3 access refused, 4 device operation failed, 5 read-back mismatch, 6 backup problem; backup prints no result line and sent: lines appear only when an operation returned a report
- [Phase 02]: A curve file is refused when it is not a regular file, exceeds 64 KB, does not decode or holds more than five bands; the device part of ja11-eq was compiled but not run before plan 02-04

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

Last session: 2026-10-10T15:55:29.109Z
Stopped at: Completed 02-03-PLAN.md
Resume file: None
