---
phase: 04-packaging
plan: 01
subsystem: packaging
tags: [macos, app-bundle, codesign, readme]
requires: [phase-03-app-ui]
provides: [scripts/make-app.sh, README.md]
affects: [.gitignore]
key-files:
  created: [scripts/make-app.sh, README.md]
  modified: [.gitignore]
decisions:
  - "No icon produced (D-06): generic app icon shipped"
status: complete
commits: 3
plan_head_before: c3234b969a969a48a1d3989a40d3955785ba7ecf
plan_head_after: aaf057ce692badeb192c85e4e430ddc449ab7a66
actuals:
  tokens: 6000
  tasks: 3
  commits: 3
---

# Phase 4 Plan 01: Packaging Summary

One script (`scripts/make-app.sh`) builds the release `JA11EQ` and assembles an ad-hoc signed `dist/JA11 EQ.app`, plus an owner-facing README written from the code as built.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 script + .gitignore | 7561c3f | Runs from any cwd, exits 0; layout, plist lint, codesign verify, no entitlements, dist/ ignored |
| 2 README | 8089a83 | All D-07 sections; commands, titles, paths taken from source |
| 3 checks | aaf057c | Second run exits 0; bundled binary still running after 5 s then stopped, no process left; swift test 302/302; no changes under dist/Sources/Tests/Package.swift |

The script removes only `$ROOT/dist/JA11 EQ.app` (suffix-guarded, root from script location).

No icon was produced (D-06); the generic app icon is used.

## Deviations from Plan

None. The README initially had `ja11-probe [--watch]`; a literal `ja11-probe --watch` mention was added to satisfy the plan's check.

## Human checks pending (D-10)

Owner to double-click `dist/JA11 EQ.app` with the JA11 plugged in; confirm it connects, Apply works, whether Input Monitoring is requested, and that the README restore steps (Device, Restore Original...) bring back the original USER1. Report any wrong README step. Executor sent nothing to the dongle beyond the app's read on connect.

## Known Stubs

None.

## Self-Check: PASSED
