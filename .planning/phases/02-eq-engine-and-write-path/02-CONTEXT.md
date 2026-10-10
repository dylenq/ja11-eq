# Phase 2: EQ Engine and Write Path - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning
**Source:** Approved implementation plan (`~/.claude/plans/i-have-connected-a-agile-treasure.md`) plus what Phase 1 established on the real device (`01-01-SUMMARY.md`, `01-02-SUMMARY.md`, `01-VERIFICATION.md`).

<domain>
## Phase Boundary

Phase 2 makes it possible to put a 5-band curve with pre-gain into the JA11's USER1 slot safely, from the command line: an EQ model that clamps to device limits, the response math and auto pre-gain the app will need, SET-frame encoding, an apply operation that is confirmed by read-back, backup and restore of the original USER1 contents, preset switching, and recovery if the dongle drops off USB after a save.

This is the first phase that writes to the DAC. No GUI: everything is driven by `JA11Kit` and a command-line tool. The SwiftUI app is Phase 3.

Phase 1 facts this phase builds on: the JA11 answers GET requests in the zero-padded 20-byte form on report `0x02`; input reports are 21 bytes with a leading `02`; the transport must call `IOHIDManagerOpen` before activation; `HIDTransport.send` currently refuses every non-GET frame; the device currently holds USER1 = slot 3 active, pre-gain 0.0 dB, five bands all at 0.0 dB (low-shelf 59 Hz Q 0.70, peak 181 Hz Q 0.62, peak 704 Hz Q 1.20, peak 7171 Hz Q 1.50, high-shelf 3973 Hz Q 0.40).

</domain>

<decisions>
## Implementation Decisions

### Protocol
- **D-01:** SET frame is `AA 0A 00 00 <cmd> <len> <data…> 00 EE`, zero-padded to 20 bytes, sent as output report `0x02` — the same padded form the device answers for GET. Payloads: pre-gain `0x17` len 2 = int16 big-endian of dB × 10 (two's complement); filter count `0x18` len 1; filter `0x15` len 8 = `index, gain int16 BE (dB × 10), frequency uint16 BE (Hz), Q uint16 BE (× 100), type (0 peak, 1 low shelf, 2 high shelf), 0x00`; preset switch `0x16` len 1 = slot; save `0x19` len 1 = slot. Reference frame: filter 0, +6.0 dB, 100 Hz, Q 0.70, low shelf → `AA 0A 00 00 15 08 00 00 3C 00 64 00 46 01 00 EE`.
- **D-02:** The send gate in `HIDTransport` is replaced deliberately by an explicit allow-list, not removed: GET frames as today, plus SET frames for exactly commands `0x15`, `0x16`, `0x17`, `0x18`, `0x19`. A save (`0x19`) is accepted only for slot 3. A preset switch (`0x16`) is accepted only for slots 0–4. A filter index must be 0–4 and a filter count 0–5. Everything else is refused before it reaches IOKit.
- **D-03:** Reset commands (`0x1B`, `0x1C`), firmware/name commands (`0x0B`, `0x30`) and the chip-vendor reports (`0x4B`, `0x54`) are never encoded and never sent. No constant for them exists in the code.
- **D-04:** Replies carry a varying byte before `EE` that Phase 1 did not explain. Before the first SET frame, collect that byte across the existing GET replies and test the obvious checksum hypotheses (sum, XOR, over payload with and without header); record the finding. SET frames use `00` in that position, as the reference implementation does. If the device ignores SET frames, that is a stop-and-report condition — do not guess at checksum bytes on write frames.

### Model and math (no device needed)
- **D-05:** `EQCurve`: pre-gain plus exactly five bands, each with type, frequency, gain, Q and an enabled flag. `Codable` (JSON). A `clamped()` operation forces every value into device limits before encoding: gain −12…+12 dB, Q 0.1–10, frequency 20–20000 Hz, pre-gain −12…+12 dB, at most 5 bands; values round to the wire resolution (gain and pre-gain 0.1 dB, Q 0.01, frequency 1 Hz).
- **D-06:** A disabled band is written to the device with 0.0 dB gain and its other values unchanged; the filter count written is always 5.
- **D-07:** Response math uses RBJ Audio EQ Cookbook biquads — peaking, low shelf, high shelf (shelf slope expressed through Q) — evaluated at a nominal 96 kHz sample rate. `response(at:)` returns the combined magnitude in dB of all enabled bands plus pre-gain; a variant without pre-gain is available for the graph.
- **D-08:** Auto pre-gain = −max(0, peak of the combined band response over 20 Hz–20 kHz on a log grid of at least 512 points), rounded down to 0.1 dB, clamped to −12…0 dB.

### Apply, verify, recover
- **D-09:** Apply order: select slot 3 first if it is not already the active slot (confirmed by read-back, so filter writes can never land in a factory preset's working copy) → pre-gain → filter count → each filter 0…4 → save to slot 3 → select slot 3, with a short pause (about 100 ms) between frames as the reference implementation does.
- **D-10:** After the save, wait for the device to be usable again (it may drop off USB and re-enumerate; allow up to about 10 s), then read the state back and compare with what was sent at wire resolution. A mismatch, or no read-back, is reported as a failure — never as success.
- **D-11:** Only slot 3 (USER1) is ever saved to. The library offers no way to save to another slot.
- **D-12:** Preset switching between Vocal (0), Classic (1), Bass (2), USER1 (3) and Off (4) is a separate operation, confirmed by reading the slot back.

### Backup and restore
- **D-13:** Before the first write of any kind, the current device state is saved to `~/Library/Application Support/JA11 EQ/user1-original.json` (slot that was active, pre-gain, five bands, timestamp). If that file already exists it is never overwritten. If the active slot is not 3 at backup time, the tool switches to slot 3 to read USER1's contents and records the slot that was active.
- **D-14:** Restore writes the backed-up curve to USER1 through the normal apply path, re-selects the originally active slot, and confirms by read-back.

### Command line
- **D-15:** `ja11-probe` stays strictly read-only (LINK-04) and is not given write commands. Writes live in a second executable, `ja11-eq`, with subcommands: `backup`, `apply <curve.json>`, `apply --test-curve`, `restore`, `slot <vocal|classic|bass|user1|off>`, each printing what it sent and what it read back, with distinct exit statuses for mismatch and no-device.
- **D-16:** The built-in test curve is: pre-gain −6.0 dB; band 0 low shelf 100 Hz +6.0 dB Q 0.70; band 1 peak 1000 Hz −3.0 dB Q 1.00; bands 2–4 left as the device's original values at 0.0 dB. It exercises positive gain, negative gain and non-zero pre-gain, which Phase 1 could not observe.

### First contact with writes (device procedure)
- **D-17:** Writes are introduced in order of reversibility, stopping at the first unexpected result: (1) backup; (2) preset switch away and back, confirmed by read-back; (3) an identity apply — the device's own current USER1 values written back unchanged — to learn save and re-enumeration behaviour without changing the sound; (4) the test curve, confirmed by read-back; (5) restore, confirmed by read-back.
- **D-18:** The phase ends with the dongle restored to its original USER1 contents and originally active slot, unless the user asks otherwise.
- **D-19:** The phase summary records what the device showed: whether it re-enumerates after a save and for how long; whether pre-gain reads back at × 10 scale; whether negative gains read back correctly; whether a factory preset's filters can be read by selecting its slot; and the D-04 trailing-byte finding.

### Claude's Discretion
- Type and file names beyond those fixed above; where the model, DSP and apply code live under `Sources/JA11Kit/`
- Exact pause lengths and timeouts, within the orders of magnitude given
- JSON key names for curves and the backup file
- Output wording of `ja11-eq`
- Whether factory-preset contents are recorded in the summary when they turn out to be readable

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Device and protocol
- `.planning/PROJECT.md` — § Context (protocol, device limits, open questions), § Constraints (safety rules: USER1 only, clamp everything, back up before the first write)
- `.planning/phases/01-device-link/01-01-SUMMARY.md` and `01-02-SUMMARY.md` — what the device showed, the transport variant that works, deviations
- External reference implementation (0BSD): `github.com/jeromeof/devicePEQ`, `devicePEQ/fiioUsbHidHandler.js` (`setPeqParams`, `setGlobalGain`, `setPeqCounter`, `setPresetPeq`, `saveToDevice`, `pushToDevice`)

### Existing code to extend
- `Sources/JA11Kit/Protocol/FiioFrame.swift`, `Sources/JA11Kit/Protocol/JA11Commands.swift` — GET codec, `isGetRequest`
- `Sources/JA11Kit/HID/HIDTransport.swift` — the send gate to replace per D-02
- `Sources/JA11Kit/Device/JA11Device.swift` — read API, watch, reply waiting
- `Sources/JA11Kit/Model/EQModel.swift` — `PresetSlot`, `FilterType`, `Band`, `EQState`
- `Tests/JA11KitTests/` — fake transport and existing suites

### Scope
- `.planning/ROADMAP.md` — Phase 2 goal and five success criteria
- `.planning/REQUIREMENTS.md` — WRITE-01 … WRITE-10

</canonical_refs>

<specifics>
## Specific Ideas

- The Mac is currently outputting to the JA11 at 352.8 kHz; whether the on-board EQ is active at that rate is unknown. The audible check is a human check at the end of the phase; if the test curve is confirmed by read-back but not audible, lowering the output sample rate in Audio MIDI Setup is the first thing to try. This feeds v2 requirement CONV-04, it does not block the phase.
- Human checks at the end of the phase (cannot be automated): the test curve is audible (bass lift); after unplugging and replugging the dongle the curve still reads back from USER1.
- Unit tests must cover, without the device: the D-01 reference frame byte-for-byte; negative gain and pre-gain encoding; every refusal in D-02 and D-03; clamping of each out-of-range field; response values at known points (a +6 dB peak reads +6 dB at its centre frequency, a shelf reaches its gain well beyond the corner, a flat curve is 0 dB everywhere); auto pre-gain for boost-only, cut-only and mixed curves; apply order and read-back comparison on the fake transport, including mismatch, no reply, and disconnect-then-reconnect after save.

</specifics>

<deferred>
## Deferred Ideas

- Live preview while dragging, Q correction for realised bandwidth, sample-rate warning — v2 (CONV-02, CONV-03, CONV-04)
- SwiftUI window, graph, preset picker — Phase 3
- `.app` bundle and README — Phase 4
- Preset library, AutoEQ import/export — v2

</deferred>

---

*Phase: 02-eq-engine-and-write-path*
*Context gathered: 2026-10-10 from the approved implementation plan and Phase 1 device evidence*
