# Requirements: JA11 EQ

**Defined:** 2026-10-10
**Core Value:** Edit an EQ curve on the Mac, press Apply, and the JA11 plays with that curve — reliably, and without ever damaging the dongle's factory presets.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Device Link

- [x] **LINK-01**: The JA11 (VID `0x2972`, PID `0x0102`) is found automatically when it is connected, with no manual selection
- [x] **LINK-02**: Connection status follows the dongle being unplugged and plugged back in, without restarting
- [x] **LINK-03**: The DAC's active preset slot, pre-gain and all filter settings can be read from the device
- [x] **LINK-04**: A `ja11-probe` command prints the DAC's current slot, pre-gain and filters without changing anything on the device
- [x] **LINK-05**: The dongle's volume and play/pause buttons keep working while the device is open
- [x] **LINK-06**: If macOS refuses access to the device, the user is told which permission to grant and where

### EQ Engine and Write Path

- [ ] **WRITE-01**: A 5-band curve plus pre-gain can be written to the DAC's USER1 slot and made the active preset
- [ ] **WRITE-02**: After a write, the device is read back and any mismatch with what was sent is reported
- [ ] **WRITE-03**: A written curve is still on the DAC after it is unplugged and plugged back in
- [ ] **WRITE-04**: Factory presets (Vocal, Classic, Bass) are never modified — only slot 3 is ever written
- [ ] **WRITE-05**: Every value is clamped to device limits (5 bands, gain ±12 dB, Q 0.1–10, pre-gain ±12 dB, 20 Hz–20 kHz) before it is sent
- [ ] **WRITE-06**: The DAC's original USER1 contents are saved to a file before the first write, and can be restored from it
- [ ] **WRITE-07**: If the dongle drops off USB after a save, the link recovers on its own and state is re-read
- [ ] **WRITE-08**: The active preset can be switched between Vocal, Classic, Bass, USER1 and Off
- [ ] **WRITE-09**: The combined frequency response of a curve (peak, low shelf, high shelf) can be computed for display
- [ ] **WRITE-10**: A pre-gain that offsets the curve's largest boost can be computed automatically, clamped to −12…0 dB

### App

- [ ] **APP-01**: User sees whether the DAC is connected and which preset is active
- [ ] **APP-02**: User can switch preset from a picker: Vocal / Classic / Bass / Custom / Off
- [ ] **APP-03**: User can set each band's type (peak, low shelf, high shelf), frequency, gain and Q
- [ ] **APP-04**: User can turn each band on or off
- [ ] **APP-05**: User sees a frequency response graph (20 Hz–20 kHz, log scale) that updates as the curve is edited
- [ ] **APP-06**: User can drag a band's handle on the graph to change its frequency and gain
- [ ] **APP-07**: User can set pre-gain by hand, or switch on Auto so it follows the curve
- [ ] **APP-08**: User can press Apply to send the curve to the DAC, and sees whether it was confirmed
- [ ] **APP-09**: When the DAC connects, the editor loads the curve currently stored on it
- [ ] **APP-10**: User sees the DAC's current output sample rate

### Packaging

- [ ] **PKG-01**: One script builds a double-clickable `JA11 EQ.app`
- [ ] **PKG-02**: A README explains how to build, run, grant permission if needed, and restore the original USER1 curve

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Presets

- **PRESET-01**: User can save the current curve under a name on the Mac
- **PRESET-02**: User can load, rename and delete saved curves
- **PRESET-03**: App ships with a few starter curves (Flat, Bass boost, …)

### Import / Export

- **IO-01**: User can import an AutoEQ / Equalizer APO `ParametricEQ.txt` file, trimmed to 5 bands
- **IO-02**: User can export the current curve in the same format

### Convenience

- **CONV-01**: Menu bar item for switching presets without opening the window
- **CONV-02**: Live preview while dragging, if the device applies filter writes before a save
- **CONV-03**: Q correction so realised peak width matches the graph at high gain
- **CONV-04**: Warning when the on-board EQ is bypassed at the current sample rate, if testing shows that happens

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Software / system-wide EQ on the Mac | User chose on-device EQ; needs a virtual audio driver |
| Other FiiO / KT Micro dongles | Only the JA11 is available to verify against |
| Writing to factory preset slots | Built-in presets cannot be re-created if overwritten |
| Firmware update or the KT Micro vendor channel (reports `0x4B` / `0x54`) | Risk of bricking; not needed for EQ |
| App Store, sandboxing, notarization | Personal local build |
| Windows / Linux / browser version | User chose a native Mac app |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LINK-01 | Phase 1 | Complete |
| LINK-02 | Phase 1 | Complete |
| LINK-03 | Phase 1 | Complete |
| LINK-04 | Phase 1 | Complete |
| LINK-05 | Phase 1 | Complete |
| LINK-06 | Phase 1 | Complete |
| WRITE-01 | Phase 2 | Pending |
| WRITE-02 | Phase 2 | Pending |
| WRITE-03 | Phase 2 | Pending |
| WRITE-04 | Phase 2 | Pending |
| WRITE-05 | Phase 2 | Pending |
| WRITE-06 | Phase 2 | Pending |
| WRITE-07 | Phase 2 | Pending |
| WRITE-08 | Phase 2 | Pending |
| WRITE-09 | Phase 2 | Pending |
| WRITE-10 | Phase 2 | Pending |
| APP-01 | Phase 3 | Pending |
| APP-02 | Phase 3 | Pending |
| APP-03 | Phase 3 | Pending |
| APP-04 | Phase 3 | Pending |
| APP-05 | Phase 3 | Pending |
| APP-06 | Phase 3 | Pending |
| APP-07 | Phase 3 | Pending |
| APP-08 | Phase 3 | Pending |
| APP-09 | Phase 3 | Pending |
| APP-10 | Phase 3 | Pending |
| PKG-01 | Phase 4 | Pending |
| PKG-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-10*
*Last updated: 2026-10-10 after roadmap creation*
