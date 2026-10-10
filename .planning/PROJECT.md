# JA11 EQ

## What This Is

JA11 EQ is a native macOS app that programs the built-in 5-band parametric equalizer of a FiiO JadeAudio JA11 USB DAC dongle. It talks to the dongle over USB HID, so the EQ is stored in the DAC itself and follows it to a phone or another computer. It is a personal tool for the owner of the dongle, replacing FiiO's own configuration app on the Mac.

## Core Value

Edit an EQ curve on the Mac, press Apply, and the JA11 plays with that curve — reliably, and without ever damaging the dongle's factory presets.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] App detects the JA11 automatically and follows plug/unplug
- [ ] App reads the DAC's current preset slot, pre-gain and filters and shows them
- [ ] User can switch between Vocal / Classic / Bass / Custom (USER1) / Off
- [ ] User can edit 5 bands: type (peak, low shelf, high shelf), frequency, gain (±12 dB), Q (0.1–10), on/off
- [ ] Live frequency response graph of the combined curve, with band handles that can be dragged
- [ ] Pre-gain control with an Auto mode that offsets the largest boost to avoid clipping
- [ ] Apply writes the curve to the DAC's USER1 slot and confirms by reading it back
- [ ] Ships as a double-clickable `JA11 EQ.app`

### Out of Scope

- Preset library (save/load named curves on the Mac) — not picked for v1; the DAC holds the one custom curve
- AutoEQ / Equalizer APO import and export — not picked for v1
- Menu bar item — user chose a single-window app
- Software / system-wide EQ on the Mac — user chose on-device EQ; a virtual audio driver is a much bigger build
- Other FiiO / KT Micro dongles — only the JA11 is on hand to verify against
- Overwriting factory presets (slots 0–2) — only USER1 is writable; never risk the built-ins
- App Store distribution, sandboxing, notarization — local ad-hoc signed build is enough for personal use

## Context

**Device as observed on this Mac (2026-10-10):**
- `JadeAudio JA11`, manufacturer `FIIO`, USB VID `0x2972`, PID `0x0102`, bcdDevice `0x0220`
- Default audio output, 2 channels, currently running at 352.8 kHz
- USB interfaces: 0 = Audio Control, 1 = Audio Streaming, 2 = HID
- HID top-level usage: Consumer Control (page `0x0C`, usage `0x01`); max input/output report size 21 bytes
- HID report descriptor: `050c0901a1018501150025017501950209e909ea8102950209cd09cf8102950481010601ff854b7508950a09018103950a0902910285547508950a09038103950a0904910285027508951409018103951409029102c0`

| Report ID | Size | Purpose |
|---|---|---|
| `0x01` | 1 byte in | Volume up/down, play/pause buttons |
| `0x4B`, `0x54` | 10 bytes in/out | Chip vendor (KT Micro) channel — unused |
| `0x02` | 20 bytes in/out | FiiO EQ command channel |

**Protocol** — from the open-source (0BSD) project `jeromeof/devicePEQ` (`devicePEQ/fiioUsbHidHandler.js`, and the `"JadeAudio JA11"` entry in `devicePEQ/usbDeviceConfig.js`):

- Commands go out as output report `0x02`, zero-padded to 20 bytes:
  - SET: `AA 0A 00 00 <cmd> <len> <data…> 00 EE`
  - GET: `BB 0B 00 00 <cmd> <len> <data…> 00 EE`
- Replies arrive as input report `0x02`: `BB 0B .. .. <cmd> <len> <data…>` — command at byte 4, data from byte 6.
- Commands:
  - `0x16` preset slot — `0` Vocal, `1` Classic, `2` Bass, `3` USER1, `4` = EQ off
  - `0x18` filter count (max 5)
  - `0x17` pre-gain — int16 big-endian, dB × 10
  - `0x15` filter — `index, gain (int16 BE, dB × 10, two's complement), freq (uint16 BE, Hz), Q (uint16 BE, × 100), type (0 peak, 1 low shelf, 2 high shelf)`
  - `0x19` save to slot
- Reference frame: filter 0, +6.0 dB, 100 Hz, Q 0.70, low shelf → `AA 0A 00 00 15 08 00 00 3C 00 64 00 46 01 00 EE`
- Reference apply order: pre-gain → filter count → each filter → save to slot.
- Limits: 5 bands; gain ±12 dB; Q 0.1–10; pre-gain ±12 dB; filter types peak / low shelf / high shelf only.
- devicePEQ marks the JA11 `disconnectOnSave: true` — the dongle may briefly drop off USB after a save.

**Open questions to settle on the real device:**
- Does the JA11 answer GET requests? (devicePEQ says it supports read.) If not: write-only, remembering the last applied curve locally.
- Does macOS require Input Monitoring permission to open this HID interface (its top-level usage is Consumer Control)?
- Is a filter write audible before the save command? Decides live preview while dragging vs. an explicit Apply button only.
- Pre-gain scale: devicePEQ's FiiO handler uses × 10, but notes another tool uses a different scale on a lookalike device. Verify by read-back and by ear.
- Is the on-board EQ active at 352.8 kHz? Some dongles bypass DSP at high sample rates.
- Q accuracy: devicePEQ found some FiiO models realise wider peaks than requested at high gain, but applies no correction for the JA11. v1 sends Q as-is.

**Development machine:** macOS 27.0 (Apple silicon), Xcode with Swift 6.4, Node 26, Homebrew. No Rust toolchain.

## Constraints

- **Tech stack**: Swift package, SwiftUI + IOKit HID + CoreAudio, macOS 14+, zero third-party dependencies — the Xcode toolchain is already installed and nothing else is needed
- **Hardware**: 5 bands, ±12 dB, Q 0.1–10, peak/shelf filters only — fixed by the dongle's firmware
- **Safety**: writes target slot 3 (USER1) only, and every value is clamped to device limits before encoding — the dongle is the user's only unit and factory presets cannot be re-created
- **Safety**: record the dongle's existing USER1 contents before the first write — so the original state can be restored
- **Compatibility**: open the HID device non-exclusively — the dongle's volume and play buttons must keep working
- **Distribution**: unsandboxed, ad-hoc signed local build — personal use only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native SwiftUI Mac app, single window | User's choice; auto-detects the DAC, no browser, can read the Mac's sample rate | — Pending |
| EQ runs on the DAC, not in software | User's choice; setting travels with the dongle to other devices | — Pending |
| v1 extras: response graph with draggable bands, auto pre-gain | User's choice; preset library and AutoEQ import declined | — Pending |
| Swift package with a `JA11Kit` library, a `ja11-probe` CLI and the app | Protocol and DSP are testable without a GUI or the device; the probe proves the link before any UI exists | — Pending |
| Protocol taken from `jeromeof/devicePEQ` (0BSD) | Working, permissively licensed reference for the exact device | — Pending |
| Only USER1 is ever written | Protects factory presets | — Pending |
| Four phases: device link → EQ engine and write path → app UI → packaging | Each phase ends in something verifiable on the real device | — Pending |
| GSD workflow with graphify knowledge graph | User's global default for projects | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-10 after initialization*
