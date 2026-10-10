# Phase 3: App UI - Context

**Gathered:** 2026-10-11
**Status:** Ready for planning
**Source:** Approved implementation plan (`~/.claude/plans/i-have-connected-a-agile-treasure.md`) plus what Phases 1 and 2 established (`02-04-SUMMARY.md`, `02-DEVICE-LOG.md`, `02-VERIFICATION.md`).

<domain>
## Phase Boundary

Phase 3 delivers the app itself: one SwiftUI window in which the user sees the DAC's state, edits the 5-band curve against a live frequency-response graph, and applies it to the DAC. It is a new executable target `JA11EQ` in the existing Swift package, built on `JA11Kit` exactly as it stands — `JA11Device` for reading and watching, `JA11Writer` as the only way to write, `EQCurve` / `EQResponse` for the model and the math.

Runnable with `swift run JA11EQ`. Packaging as a double-clickable `.app` is Phase 4.

Device facts that shape the UI: an apply takes about 4 seconds and the dongle drops off USB for about 0.9 s after every save, then returns; a write is not live until saved; only USER1 can be written; factory presets (Vocal, Classic, Bass) can be selected and their filters read, but not changed.

</domain>

<decisions>
## Implementation Decisions

### Structure
- **D-01:** New executable target `JA11EQ` at `Sources/JA11EQ/`, depending only on `JA11Kit`. SwiftUI `App` with a single `WindowGroup`/`Window`, macOS 14+, no third-party packages. No menu bar extra, no settings window, no document model.
- **D-02:** One `@MainActor @Observable` view model (`AppModel`) owns all UI state and is the only type that talks to `JA11Device` / `JA11Writer`. Views hold no device references. All curve logic that can be tested without a window (edit operations, dirty tracking, auto pre-gain coupling, drag-to-value mapping, state transitions) lives in types that are unit-testable from the test target — either in `JA11Kit` or in a small library target the app and tests both use — not inside `View` bodies.
- **D-03:** The app never constructs frames and never calls `JA11Device.apply` directly: every write goes through `JA11Writer` (`apply`, `restore`, `selectSlot`), so the backup-first rule holds in the app too.

### Device header (APP-01, APP-02, APP-09, APP-10)
- **D-04:** The header shows connection status (Connected / Not connected / Access refused, with the Input Monitoring instruction text from `JA11Error` for the refused case), the active preset, and the DAC's current output sample rate.
- **D-05:** Connection follows the device through `JA11Device.watch()`: unplug and replug update the status and reload state without restarting the app.
- **D-06:** Preset picker with five entries: Vocal, Classic, Bass, Custom (USER1), Off. Choosing one calls `JA11Writer.selectSlot` and shows the slot read back. The picker is disabled while an operation is in flight or the device is disconnected.
- **D-07:** Sample rate is read with CoreAudio from the output device whose name is `JadeAudio JA11` (nominal sample rate), shown as e.g. `352.8 kHz`, and updated when it changes. Display only — the app does not change the sample rate. If the audio device is not found, show `—`.
- **D-08:** When the DAC connects, the editor loads the state read from it. When a factory preset or Off is active, the editor shows that slot's filters read-only (controls disabled, with a one-line note that only Custom can be edited); selecting Custom makes the editor editable again.

### Editor (APP-03, APP-04)
- **D-09:** Five band rows, always five. Each row: on/off toggle, type picker (Peak, Low shelf, High shelf), frequency (20–20000 Hz), gain (−12…+12 dB, 0.1 steps), Q (0.1–10, 0.01 steps). Every edit passes through `EQCurve.clamped()` semantics, so the UI can never hold an out-of-range value.
- **D-10:** Frequency input is logarithmic (slider or drag feels even across octaves) with an exact numeric field beside it; gain and Q have a slider plus numeric field.
- **D-11:** The editor tracks whether the edited curve differs from what was last read from or applied to the DAC ("unsaved changes"), shown next to the Apply button. A "Revert" action discards edits and reloads the device's state.

### Graph (APP-05, APP-06)
- **D-12:** Frequency-response graph drawn with SwiftUI `Canvas`: x axis logarithmic 20 Hz–20 kHz with gridlines and labels at 20, 50, 100, 200, 500, 1k, 2k, 5k, 10k, 20k; y axis ±15 dB with gridlines every 3 dB and a distinct 0 dB line. It draws the combined response of the enabled bands (without pre-gain) as the main curve, using `EQResponse`, and redraws on every edit.
- **D-13:** One handle per band at (band frequency, band gain), numbered 1–5, visually distinct when the band is off. Dragging a handle changes that band's frequency (x) and gain (y), clamped to device limits; the row's fields and the curve follow during the drag. Scrolling over a handle (or a modifier-drag) adjusts Q.
- **D-14:** A second, fainter line shows the response including pre-gain, so the effect of pre-gain on headroom is visible; any part of that line above 0 dB is marked as a clipping risk.

### Pre-gain (APP-07)
- **D-15:** Pre-gain control with a slider (−12…+12 dB, 0.1 steps), a numeric field, and an Auto toggle. With Auto on, pre-gain is set from `EQResponse.autoPreGain` after every edit and the slider is disabled; with Auto off, the user sets it by hand. Auto defaults to on for a curve the user starts editing, and is off when the value loaded from the DAC does not equal what Auto would compute.

### Apply (APP-08)
- **D-16:** An Apply button sends the edited curve with `JA11Writer.apply`. While it runs (about 4 s, including the USB drop) the UI shows progress, disables Apply / Revert / the preset picker, and does not treat the mid-apply disconnect as "device unplugged".
- **D-17:** The outcome is shown plainly: "Applied and confirmed" when the read-back matches; on a mismatch, the list of differences from `ApplyReport.differences`; on an error, the `JA11Error` description. A mismatch or error is never shown as success, and the editor stays dirty.
- **D-18:** Apply is enabled only when the device is connected, Custom is the editable target, no operation is in flight, and there are unsaved changes. Applying while a factory preset is active is not offered: the user selects Custom first (D-08).
- **D-19:** The watch loop and write operations must not collide: `JA11Device` reports `.busy` / `.writeInterrupted` if an apply starts while a read is in flight (see `02-02-SUMMARY.md`). The app serialises device operations so a user-initiated apply or slot switch waits for an in-flight read instead of failing, and the watch loop does not re-read during an apply.
- **D-20:** A "Restore original" action (menu item or secondary button, with a confirmation dialog) calls `JA11Writer.restore` to put back the USER1 contents backed up before the first ever write.

### Look and behaviour
- **D-21:** Native macOS appearance following system light/dark mode, system font, standard controls, accent colour for the main curve. Window has a sensible minimum size (about 760 × 560) and the graph grows with the window. No custom chrome.
- **D-22:** With no dongle connected the window still opens: the editor is disabled and the header says how to proceed ("Plug in the JA11"). The app never crashes or blocks on a missing device.

### Claude's Discretion
- View decomposition and file names under `Sources/JA11EQ/`; whether a small extra library target is introduced for testable UI logic (D-02)
- Exact layout, spacing, colours within D-21; number formatting
- How Q is adjusted from the graph (scroll vs. modifier-drag)
- CoreAudio listener details for D-07
- Wording of status and error texts beyond those taken from `JA11Error`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Library the app is built on
- `Sources/JA11Kit/Device/JA11Writer.swift` — the only write door: `backup`, `apply`, `applyTestCurve`, `restore`, `selectSlot`, and their report types
- `Sources/JA11Kit/Device/JA11Device.swift` — `readState`, `watch`, `JA11Error`, timing parameters, `.busy` / `.writeInterrupted`
- `Sources/JA11Kit/Model/EQCurve.swift`, `Sources/JA11Kit/Model/EQModel.swift` — `EQCurve`, `clamped()`, `deviceState()`, `EQState`, `PresetSlot`, `FilterType`, `Band`
- `Sources/JA11Kit/DSP/EQResponse.swift` — `bandResponse`, `response`, `logGrid`, `autoPreGain`
- `Sources/JA11Kit/Protocol/JA11Commands.swift` — `JA11Limits`
- `Sources/ja11-eq/main.swift` — a working example of driving `JA11Writer` end to end
- `Tests/JA11KitTests/FakeDongle.swift` — the in-memory dongle for tests

### Device behaviour
- `.planning/phases/02-eq-engine-and-write-path/02-04-SUMMARY.md` and `02-DEVICE-LOG.md` — apply timing, the ~0.9 s USB drop after a save, factory presets readable by selecting their slot
- `.planning/phases/02-eq-engine-and-write-path/02-02-SUMMARY.md` — busy / write-interrupted behaviour when a read is in flight

### Scope
- `.planning/ROADMAP.md` — Phase 3 goal and five success criteria
- `.planning/REQUIREMENTS.md` — APP-01 … APP-10
- `.planning/PROJECT.md` — § Constraints

</canonical_refs>

<specifics>
## Specific Ideas

- The dongle currently holds the Phase 2 test curve in USER1 (pre-gain −6.0 dB; low shelf 100 Hz +6.0 dB Q 0.70; peak 1000 Hz −3.0 dB Q 1.00; three bands at 0 dB). That is a useful non-flat state for checking that the editor and graph load real device values. Automated checks in this phase may read the device and may launch the app; they must NOT apply, restore or switch presets on the real dongle — writes from the GUI are exercised by the human at the end of the phase.
- Human checks at the end of the phase (cannot be automated): the window shows connected status, preset and sample rate; unplug/replug updates the header and reloads; each preset in the picker switches the DAC; editing fields and dragging handles move the curve; Auto pre-gain follows edits; Apply sends the curve and reports "confirmed"; the result is audible.
- Unit tests must cover, without a window or the device: every edit operation clamps; dirty tracking against the last device state; Auto pre-gain coupling on and off; graph coordinate mapping in both directions (frequency↔x on a log axis, gain↔y) including the edges; drag updates clamped at the limits; the apply state machine (idle → applying → confirmed / mismatch / error) on the fake dongle, including the mid-apply disconnect not being reported as unplugged; factory preset selected ⇒ editor read-only and Apply disabled.

</specifics>

<deferred>
## Deferred Ideas

- `.app` bundle, icon, README, Input Monitoring check for a double-clicked app — Phase 4
- Preset library, AutoEQ import/export, menu bar item — v2
- Live preview while dragging, Q correction, sample-rate warning or switching — v2 (CONV-02, CONV-03, CONV-04)

</deferred>

---

*Phase: 03-app-ui*
*Context gathered: 2026-10-11 from the approved implementation plan and Phase 1–2 device evidence*
