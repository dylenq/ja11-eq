# Roadmap: JA11 EQ

## Overview

JA11 EQ goes from an empty repo to a double-clickable Mac app in four steps, each ending in something that can be checked on the real dongle. First the Mac learns to find the JA11 and read its EQ state without changing anything. Then the EQ engine and the write path make it possible to put a curve into the DAC's USER1 slot safely, confirm it by read-back, and get the original back. Then a SwiftUI window puts the whole edit → apply → read-back loop in front of the user. Last, one script packages it as `JA11 EQ.app`, with a README.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Device Link** - Find the JA11 over USB HID and read its slot, pre-gain and filters with a read-only `ja11-probe` CLI
- [ ] **Phase 2: EQ Engine and Write Path** - Write a clamped curve to USER1, confirm it by read-back, keep it across a replug, and be able to restore the original
- [ ] **Phase 3: App UI** - SwiftUI window with device header, 5-band editor, draggable response graph, pre-gain with Auto, and Apply
- [ ] **Phase 4: Packaging** - One script builds an ad-hoc signed, double-clickable `JA11 EQ.app`, plus a README

## Phase Details

### Phase 1: Device Link

**Goal**: The Mac finds the JA11 on its own, stays linked across unplug and replug, and reads the DAC's real EQ state — without changing anything on the device.
**Depends on**: Nothing (first phase)
**Requirements**: LINK-01, LINK-02, LINK-03, LINK-04, LINK-05, LINK-06
**Success Criteria** (what must be TRUE):
  1. With the JA11 plugged in, running `ja11-probe` with no arguments finds the dongle by itself and prints its active preset slot, pre-gain and every filter (type, frequency, gain, Q) as read from the device.
  2. Running the probe changes nothing on the DAC: it only ever sends GET (`BB 0B`) frames, two runs in a row print identical values, and the active preset is the same before and after.
  3. With the probe left running, unplugging the dongle is reported as disconnected and plugging it back in as connected, with the state read again — no restart needed.
  4. While the probe has the device open, the dongle's volume and play/pause buttons still control the Mac.
  5. If macOS refuses access to the device, the probe names the permission to grant and where in System Settings to grant it, instead of a bare error.

**Plans**: 2 plans

Plans:
**Wave 1**
- [ ] 01-01-PLAN.md — Swift package, HID transport and GET codec; `ja11-probe` reads and prints slot, pre-gain and filters from the real dongle

**Wave 2** *(blocked on Wave 1 completion)*
- [ ] 01-02-PLAN.md — Failure behaviour and exit statuses, `--watch` across unplug/replug, read-only proof and device evidence

### Phase 2: EQ Engine and Write Path

**Goal**: A 5-band curve with pre-gain can be written to the DAC's USER1 slot safely — clamped to device limits, confirmed by read-back, kept across a replug, with the original USER1 recoverable and the factory presets untouched.
**Depends on**: Phase 1
**Requirements**: WRITE-01, WRITE-02, WRITE-03, WRITE-04, WRITE-05, WRITE-06, WRITE-07, WRITE-08, WRITE-09, WRITE-10
**Success Criteria** (what must be TRUE):
  1. From the command line, a test curve (5 bands plus pre-gain) is written to the DAC, USER1 becomes the active preset, the read-back matches what was sent, and the change can be heard in playback; when the read-back differs from what was sent, the mismatch is reported instead of being passed as success.
  2. After the dongle is unplugged and plugged back in, the same curve reads back from USER1; and if the dongle drops off USB after the save, the link comes back by itself and the state is read again, with no restart.
  3. Before the first write, the DAC's original USER1 contents are saved to a file, and restoring from that file puts USER1 back to exactly those values, confirmed by read-back.
  4. The active preset can be switched between Vocal, Classic, Bass, USER1 and Off, each confirmed by read-back; a save to any slot other than 3 is refused, and Vocal, Classic and Bass read back the same before and after a write and a restore.
  5. Without the device attached, `swift test` shows that out-of-range values (band count, gain, Q, pre-gain, frequency) are clamped to device limits before encoding, that the reference filter frame in PROJECT.md encodes byte-for-byte, that the combined response of peak, low-shelf and high-shelf bands matches known values, and that auto pre-gain offsets the curve's largest boost within −12…0 dB.

**Plans**: TBD

### Phase 3: App UI

**Goal**: The user can see the DAC's state, edit the 5-band curve against a live response graph, and apply it to the DAC — all from one window.
**Depends on**: Phase 2
**Requirements**: APP-01, APP-02, APP-03, APP-04, APP-05, APP-06, APP-07, APP-08, APP-09, APP-10
**Success Criteria** (what must be TRUE):
  1. With the JA11 plugged in, the window's device header shows it as connected, with its active preset and current output sample rate, and the editor opens loaded with the curve stored on the DAC; unplugging and replugging updates the status and reloads the curve without restarting the app.
  2. Choosing Vocal, Classic, Bass, Custom or Off in the preset picker switches the DAC's active preset, and the header shows the new one.
  3. The user can set type (peak, low shelf, high shelf), frequency, gain and Q for each of the 5 bands and turn each band on or off, and the response graph (20 Hz–20 kHz, log scale) redraws as each value changes.
  4. Dragging a band's handle on the graph changes that band's frequency and gain, with its fields and the curve following; pre-gain can be set by hand, or switched to Auto, where it follows the curve.
  5. Pressing Apply sends the curve to the DAC and the window shows whether the read-back confirmed it — the whole edit → apply → read-back loop works from the GUI alone.

**Plans**: TBD
**UI hint**: yes

### Phase 4: Packaging

**Goal**: One command builds a double-clickable `JA11 EQ.app`, and the README covers building, running, permissions and getting the original USER1 curve back.
**Depends on**: Phase 3
**Requirements**: PKG-01, PKG-02
**Success Criteria** (what must be TRUE):
  1. Running `scripts/make-app.sh` on a clean checkout produces an ad-hoc signed `JA11 EQ.app`, with no other steps.
  2. Double-clicking `JA11 EQ.app` in Finder opens the app, which connects to the JA11 and can read and apply a curve just as the development build does.
  3. The README explains how to build, run, grant permission if macOS asks for it, and restore the original USER1 curve — and following its restore steps does put the original USER1 back.

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Device Link | 0/TBD | Not started | - |
| 2. EQ Engine and Write Path | 0/TBD | Not started | - |
| 3. App UI | 0/TBD | Not started | - |
| 4. Packaging | 0/TBD | Not started | - |
