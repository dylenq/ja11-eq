---
phase: 04-packaging
verified: 2026-10-11
status: passed
score: 3/3 success criteria verified
---

# Phase 4: Packaging — Verification

Verified by the orchestrator directly (no verifier subagent was spawned for this two-file phase) and by the user on the real JA11.

## Success criteria

| # | Criterion | Evidence | Result |
|---|-----------|----------|--------|
| 1 | `scripts/make-app.sh` on a clean checkout produces an ad-hoc signed `JA11 EQ.app` with no other steps | Orchestrator ran the script: exit 0, `dist/JA11 EQ.app` created with `Contents/MacOS/JA11 EQ`, `Contents/Info.plist`, `_CodeSignature`; `plutil -lint` OK; `codesign --verify --deep --strict` passes. The executor also ran it twice from `/tmp`. | Passed |
| 2 | Double-clicking `JA11 EQ.app` opens the app, which connects to the JA11 and can read and apply a curve as the development build does | Orchestrator opened the bundle with `open` and confirmed the process was running. User then reported in the main session: "everything works" (open, connect, Apply, restore). | Passed |
| 3 | The README explains build, run, permission and restore, and its restore steps put the original USER1 back | `README.md` has sections for build and run, using it, safety, restoring the original curve, permissions, command-line tools, troubleshooting. User reported the restore worked. | Passed |

## Requirements

- PKG-01 — satisfied (criterion 1 and 2)
- PKG-02 — satisfied (criterion 3)

## Other checks

- `swift test`: 302 tests in 16 suites passed after packaging.
- No change under `Sources/`, `Tests/` or `Package.swift` in this phase; `dist/` is git-ignored.
- The script's only removal is its own previous output at `dist/JA11 EQ.app`.

## Not established

- The user did not report individually on whether macOS asked for Input Monitoring or showed a first-launch warning for the double-clicked app; "everything works" is taken as no blocking prompt. No app icon was produced (generic icon ships, CONTEXT D-06).
