# JA11 EQ

## What it is

JA11 EQ is a small macOS app for the FiiO JadeAudio JA11 USB DAC dongle. It edits the dongle's built-in five-band parametric equalizer over USB. The curve is stored inside the dongle, so it follows the JA11 to a phone or another computer. It replaces FiiO's own configuration app on the Mac.

## Requirements

- A FiiO JA11, plugged in
- macOS 14 or later
- Xcode command-line tools (to build the app yourself)

## Build and run

From the repository folder:

```
scripts/make-app.sh
open "dist/JA11 EQ.app"
```

The script builds the app in release mode and creates an ad-hoc signed `dist/JA11 EQ.app`. You can drag it into Applications if you like. Run the script again after any change to rebuild it.

Because the app is ad-hoc signed and not notarized, macOS may refuse to open it the first time. If that happens, Control-click (or right-click) the app, choose Open, and confirm. Alternatively, allow it under System Settings, Privacy & Security.

## Using it

- The preset menu offers Vocal, Classic, Bass, Custom and Off. Vocal, Classic, Bass and Off are the dongle's factory presets. Custom is the one you edit.
- Edit the five bands in the editor panel. Each band has an on/off toggle (1 to 5), a Type (Peak, Low shelf, High shelf), a frequency in Hz, a gain in dB and a Q.
- On the graph, drag a band's handle to change its frequency and gain. Option-drag to change Q.
- Pre-gain lowers the overall level to avoid clipping. The Auto toggle sets it for you.
- Apply sends the curve to the dongle. While the dongle saves, the audio drops out for roughly one second, then returns. The status reports when the dongle read the curve back correctly.
- "Unsaved changes" appears when the curve on screen differs from what is on the dongle. Revert discards those edits.
- Switching presets while you have unsaved edits asks you to confirm, because the edits to Custom are discarded.

## Safety

- Only the Custom slot (the dongle's USER1 slot) is ever written. The factory presets cannot be changed.
- Every value is clamped to the dongle's limits (5 bands, plus or minus 12 dB, Q 0.1 to 10) before it is sent.
- Before the first write, the app saves the dongle's original USER1 contents once, to `~/Library/Application Support/JA11 EQ/user1-original.json`. That file is never replaced. Do not delete it.
- The dongle is opened non-exclusively, so its volume and play buttons keep working.

## Restoring the original curve

Either way writes the backed-up original USER1 contents back to the dongle:

- In the app: choose Device, Restore Original... from the menu bar, or press the "Restore original..." button, then confirm with Restore.
- From a terminal: `ja11-eq restore`

## Permissions

If macOS refuses access to the dongle, the app shows "Access refused". Open System Settings, Privacy & Security, Input Monitoring, enable JA11 EQ, then restart the app.

## Command-line tools

Build them with `swift build`. Run them with `swift run ja11-probe` or `swift run ja11-eq`, or directly from `"$(swift build --show-bin-path)"`.

`ja11-probe` only reads the dongle and prints its state (`ja11-probe --watch` keeps running and follows plugging and unplugging):

```
ja11-probe [--watch] [--raw]
  --watch   keep running; report disconnect and connect, and read again on each connect
  --raw     also print every frame sent and received as hex
  --help    show the usage text
```

`ja11-eq` can change the dongle. `apply`, `restore` and `slot` write to it:

```
ja11-eq [--raw] <command>
  backup               save the JA11's original USER1 contents; print the backup
  apply <curve.json>   write the curve in the file to USER1 and read it back
  apply --test-curve   write the built-in test curve to USER1 and read it back
  restore              write the backed-up curve to USER1, re-select the original slot
  slot <vocal|classic|bass|user1|off>
                       make that preset the active one and read the slot back
  --raw                also print every frame sent and received as hex
  --help               show the usage text
```

A curve file is JSON with at most 5 bands; the type is `peak`, `lowShelf` or `highShelf`:

```
{"preGain": -6.0, "bands": [{"type": "peak", "frequency": 1000, "gain": -3.0, "q": 1.0}]}
```

Run `ja11-eq --help` for the exit status codes.

## Troubleshooting

- Not connected: the app shows "Plug in the JA11". Plug the dongle in; the app connects by itself.
- Access refused: see Permissions above.
- Apply reports a mismatch: the dongle read back different values than were sent. The status lists each difference. Try Apply again; if it persists, use Restore Original.
- No audible change: check that Custom is the selected preset, that the band toggles are on, and that the dongle is the audio output.

## Credits

The dongle's protocol comes from the 0BSD-licensed `jeromeof/devicePEQ` project.
