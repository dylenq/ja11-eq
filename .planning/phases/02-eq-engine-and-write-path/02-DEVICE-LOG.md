# Phase 2 Plan 04: Device Log

Every command run against the JA11 in plan 02-04, in order, with full output. Reads: ja11-probe. Writes: ja11-eq. Started 2026-10-10.

## Baseline

Command: `ja11-probe` (saved as .build/ja11-device/baseline.txt)
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-probe --raw` (saved as .build/ja11-device/baseline-raw.txt)
```text
info: input-monitoring access: unknown
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
info: reply header offset: 1
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
info: request frame form: padded
```
exit: 0

The baseline matches the expected state before the plan: slot 3 (USER1), pre-gain +0.0 dB, five filters as Phase 1 saw.

## Trailing byte (D-04)

Arithmetic only on the saved text of the raw baseline; nothing was sent. Frame = bytes from bb up to the byte before ee; header = bb 0b 00 00; payload = command, length, data. "all" = over every preceding byte, "payload" = without the four header bytes. Values in hex.

| reply | preceding bytes (bb .. last data) | byte before ee | all sum | all neg | all xor | payload sum | payload neg | payload xor |
|---|---|---|---|---|---|---|---|---|
| slot (16) | bb 0b 00 00 16 01 03 | bd | e0 | 20 | a4 | 1a | e6 | 14 |
| count (18) | bb 0b 00 00 18 01 05 | 94 | e4 | 1c | ac | 1e | e2 | 1c |
| pre-gain (17) | bb 0b 00 00 17 02 00 00 | f1 | df | 21 | a5 | 19 | e7 | 15 |
| filter 0 (15) | bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 | 7f | 65 | 9b | d1 | 9f | 61 | 61 |
| filter 1 (15) | bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 | 6e | d7 | 29 | 27 | 11 | ef | 97 |
| filter 2 (15) | bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 | 30 | 1f | e1 | 15 | 59 | a7 | a5 |
| filter 3 (15) | bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 | b5 | 9b | 65 | 27 | d5 | 2b | 97 |
| filter 4 (15) | bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 | e5 | a5 | 5b | 09 | df | 21 | b9 |

Matches out of 8: all-sum 0, all-neg 0, all-xor 0, payload-sum 0, payload-neg 0, payload-xor 0.

**Conclusion:** none of the six hypotheses fits any of the eight replies. The byte equals Phase 1 for the same content (bd, 94, f1, 7f, 6e, 30, b5, e5, as in 01-02-SUMMARY.md), so it is deterministic in the content, but it is not a plain sum, two's complement or XOR checksum. SET frames keep 00 in that position (D-04); the finding is recorded, not acted on.

## Step 1: backup

Command: `ja11-eq --raw backup`
```text
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
backup: saved /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
backup-time: 2026-10-10T18:22:11Z
original: slot: 3 (USER1)
original: pre-gain: +0.0 dB
original: filters: 5
original: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
original: filter 1: peak 181 Hz +0.0 dB Q 0.62
original: filter 2: peak 704 Hz +0.0 dB Q 1.20
original: filter 3: peak 7171 Hz +0.0 dB Q 1.50
original: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-eq backup`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
backup-time: 2026-10-10T18:22:11Z
original: slot: 3 (USER1)
original: pre-gain: +0.0 dB
original: filters: 5
original: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
original: filter 1: peak 181 Hz +0.0 dB Q 0.62
original: filter 2: peak 704 Hz +0.0 dB Q 1.20
original: filter 3: peak 7171 Hz +0.0 dB Q 1.50
original: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Backup file: `/Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json`
```json
{
  "activeSlot" : 3,
  "curve" : {
    "bands" : [
      {
        "enabled" : true,
        "frequency" : 59,
        "gain" : 0,
        "q" : 0.7,
        "type" : "lowShelf"
      },
      {
        "enabled" : true,
        "frequency" : 181,
        "gain" : 0,
        "q" : 0.62,
        "type" : "peak"
      },
      {
        "enabled" : true,
        "frequency" : 704,
        "gain" : 0,
        "q" : 1.2,
        "type" : "peak"
      },
      {
        "enabled" : true,
        "frequency" : 7171,
        "gain" : 0,
        "q" : 1.5,
        "type" : "peak"
      },
      {
        "enabled" : true,
        "frequency" : 3973,
        "gain" : 0,
        "q" : 0.4,
        "type" : "highShelf"
      }
    ],
    "preGain" : 0
  },
  "formatVersion" : 1,
  "savedAt" : "2026-10-10T18:22:11Z"
}
```

## Step 2: preset switch

Command: `ja11-eq --raw slot off`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 04 3e ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 4 (Off)
read: slot: 4 (Off)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 04 3e ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 03 e8 00 46 00 e6 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 07 d0 00 46 00 ee ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 13 88 00 46 00 8c ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1f 40 00 46 00 cb ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 27 10 00 46 00 79 ee 00 00 00 00
state: slot: 4 (Off)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 1000 Hz +0.0 dB Q 0.70
state: filter 1: peak 2000 Hz +0.0 dB Q 0.70
state: filter 2: peak 5000 Hz +0.0 dB Q 0.70
state: filter 3: peak 8000 Hz +0.0 dB Q 0.70
state: filter 4: peak 10000 Hz +0.0 dB Q 0.70
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot user1`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 3 (USER1)
read: slot: 3 (USER1)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
state: slot: 3 (USER1)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
state: filter 1: peak 181 Hz +0.0 dB Q 0.62
state: filter 2: peak 704 Hz +0.0 dB Q 1.20
state: filter 3: peak 7171 Hz +0.0 dB Q 1.50
state: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
result: confirmed
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Step 2 notes: `slot off` confirmed (read: slot: 4 (Off)), `slot user1` confirmed (read: slot: 3 (USER1)); `ja11-probe` afterwards equals the baseline. No `rx:` line directly followed a SET `tx:` line: the dongle sends no report in answer to a preset-switch frame (the next `rx:` answers the following GET). The `slot off` command printed `state:` lines, not an `info:` line: the Off slot's filters were readable (flat, peak 1000/2000/5000/8000/10000 Hz, Q 0.70, pre-gain +0.0 dB). Format note: the `sent:` line is printed after the operation, per 02-03-SUMMARY departure 2, so in the raw output the `tx: aa 0a` line comes before `sent:`.

## Factory presets before

Command: `ja11-eq --raw slot vocal`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 00 5f ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 0 (Vocal)
read: slot: 0 (Vocal)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 00 5f ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 ff ed 00 28 00 64 00 a4 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 ff cf 00 b4 00 3c 00 cd ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 32 02 58 00 46 00 bf ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 3c 08 98 00 3c 00 3a ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 ff e3 1b 58 00 64 00 06 ee 00 00 00 00
state: slot: 0 (Vocal)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 40 Hz -1.9 dB Q 1.00
state: filter 1: peak 180 Hz -4.9 dB Q 0.60
state: filter 2: peak 600 Hz +5.0 dB Q 0.70
state: filter 3: peak 2200 Hz +6.0 dB Q 0.60
state: filter 4: peak 7000 Hz -2.9 dB Q 1.00
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot classic`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 01 01 ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 1 (Classic)
read: slot: 1 (Classic)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 01 01 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 ff cf 00 e6 00 64 00 50 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 19 00 50 00 64 00 fb ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 19 09 c4 00 64 00 22 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 ff e3 17 70 00 64 00 9b ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 1f 40 00 96 00 43 ee 00 00 00 00
state: slot: 1 (Classic)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 230 Hz -4.9 dB Q 1.00
state: filter 1: peak 80 Hz +2.5 dB Q 1.00
state: filter 2: peak 2500 Hz +2.5 dB Q 1.00
state: filter 3: peak 6000 Hz -2.9 dB Q 1.00
state: filter 4: peak 8000 Hz +0.0 dB Q 1.50
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot bass`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 02 e3 ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 2 (Bass)
read: slot: 2 (Bass)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 02 e3 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 1e 00 20 00 64 00 95 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 23 00 40 00 64 00 e1 ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 19 00 64 00 64 00 78 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 19 09 c4 00 64 00 61 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 ff e3 17 70 00 64 00 4b ee 00 00 00 00
state: slot: 2 (Bass)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 32 Hz +3.0 dB Q 1.00
state: filter 1: peak 64 Hz +3.5 dB Q 1.00
state: filter 2: peak 100 Hz +2.5 dB Q 1.00
state: filter 3: peak 2500 Hz +2.5 dB Q 1.00
state: filter 4: peak 6000 Hz -2.9 dB Q 1.00
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot user1`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 3 (USER1)
read: slot: 3 (USER1)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
state: slot: 3 (USER1)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
state: filter 1: peak 181 Hz +0.0 dB Q 0.62
state: filter 2: peak 704 Hz +0.0 dB Q 1.20
state: filter 3: peak 7171 Hz +0.0 dB Q 1.50
state: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
result: confirmed
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

What was learned: all three factory slots return filters when selected (state: lines saved as vocal/classic/bass-before.txt), each different from USER1 and from each other, and not equal to the Off slot's flat 1000/2000/5000/8000/10000 Hz set. The read therefore does show factory contents. Vocal: 40 Hz -1.9, 180 Hz -4.9, 600 Hz +5.0, 2200 Hz +6.0, 7000 Hz -2.9. Classic: 230 Hz -4.9, 80 Hz +2.5, 2500 Hz +2.5, 6000 Hz -2.9, 8000 Hz +0.0 Q 1.50. Bass: 32 Hz +3.0, 64 Hz +3.5, 100 Hz +2.5, 2500 Hz +2.5, 6000 Hz -2.9. Several negative factory gains read as x.9 (-1.9, -4.9, -2.9), which is how the firmware stores them; the cause is not examined. After `slot user1`, `ja11-probe` equals the baseline.

## Step 3: identity apply

Command: `ja11-eq --raw restore`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 17 02 00 00 00 ee 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 18 01 05 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 15 08 00 00 00 00 3b 00 46 01 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 01 00 00 00 b5 00 3e 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 02 00 00 02 c0 00 78 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 03 00 00 1c 03 00 96 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 04 00 00 0f 85 00 28 02 00 ee 00 00 00 00
tx: aa 0a 00 00 19 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 16 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 45 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
sent: slot: 3 (USER1)
sent: pre-gain: +0.0 dB
sent: filters: 5
sent: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
sent: filter 1: peak 181 Hz +0.0 dB Q 0.62
sent: filter 2: peak 704 Hz +0.0 dB Q 1.20
sent: filter 3: peak 7171 Hz +0.0 dB Q 1.50
sent: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
link: disconnected +0.92s
link: connected +1.82s
read: slot: 3 (USER1)
read: pre-gain: +0.0 dB
read: filters: 5
read: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
read: filter 1: peak 181 Hz +0.0 dB Q 0.62
read: filter 2: peak 704 Hz +0.0 dB Q 1.20
read: filter 3: peak 7171 Hz +0.0 dB Q 1.50
read: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
final: slot: 3 (USER1)
result: confirmed
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Step 3 notes: the restore of the just-taken backup (identity apply) exited 0 with `result: confirmed` and `final: slot: 3 (USER1)`. Write frames in order: command 17 (pre-gain), 18 (count), 15 indices 00 to 04, 19 carrying 03, 16 carrying 03. The only 19 frame is `tx: aa 0a 00 00 19 01 03 00 ee`. Both following probes equal the baseline.
- Link: `link: disconnected +0.92s`, `link: connected +1.82s`: the dongle dropped off USB 0.92 s after the save and was back 1.82 s after it, away about 0.9 s. `ja11-eq` waited it out itself and read back afterwards; no later probe found the dongle missing.
- Command duration: about 4 s wall clock for the whole command (measured around the tool call, includes the 1.6 s save settle and the re-enumeration).
- The slot reply's byte before `ee` changed from `bd` (baseline, slot 3) to `45` (after the save) for the same content (`16 01 03`). The byte is therefore not a pure function of the frame content; see Findings.
- Format departures from the plan text: `sent:` lines are printed after the operation (02-03 departure 2); `restore` printed `backup: kept` first (departure 4); no `diff:` line appeared, as the plan expects.

## Step 4: test curve

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-eq --raw apply --test-curve`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 17 02 ff c4 00 ee 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 18 01 05 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 15 08 00 00 3c 00 64 00 46 01 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 01 ff e2 03 e8 00 64 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 02 00 00 02 c0 00 78 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 03 00 00 1c 03 00 96 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 04 00 00 0f 85 00 28 02 00 ee 00 00 00 00
tx: aa 0a 00 00 19 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 16 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 45 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 ff c4 db ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 3c 00 64 00 46 01 ad ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 ff e2 03 e8 00 64 00 b4 ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
sent: slot: 3 (USER1)
sent: pre-gain: -6.0 dB
sent: filters: 5
sent: filter 0: low-shelf 100 Hz +6.0 dB Q 0.70
sent: filter 1: peak 1000 Hz -3.0 dB Q 1.00
sent: filter 2: peak 704 Hz +0.0 dB Q 1.20
sent: filter 3: peak 7171 Hz +0.0 dB Q 1.50
sent: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
link: disconnected +0.92s
link: connected +1.83s
read: slot: 3 (USER1)
read: pre-gain: -6.0 dB
read: filters: 5
read: filter 0: low-shelf 100 Hz +6.0 dB Q 0.70
read: filter 1: peak 1000 Hz -3.0 dB Q 1.00
read: filter 2: peak 704 Hz +0.0 dB Q 1.20
read: filter 3: peak 7171 Hz +0.0 dB Q 1.50
read: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
result: confirmed
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: -6.0 dB
filters: 5
filter 0: low-shelf 100 Hz +6.0 dB Q 0.70
filter 1: peak 1000 Hz -3.0 dB Q 1.00
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Step 4 notes: `ja11-eq --raw apply --test-curve` exited 0, `result: confirmed`, eight `sent:`, eight `read:`, no `diff:`. The independent `ja11-probe` printed exactly the eight expected test-curve lines. Link: `link: disconnected +0.92s`, `link: connected +1.83s` (away about 0.9 s). The first probe in this section, before the apply, equalled the baseline (slot 3 active). D-19 answers: pre-gain -6.0 dB was sent as `ff c4` (-60) and read back as -6.0 dB, so the x10 scale holds; the -3.0 dB of filter 1 was sent as `ff e2` (-30) and read back as -3.0 dB; the +6.0 dB of filter 0 was sent as `00 3c` (60) and read back as +6.0 dB.

## Step 5: restore

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: -6.0 dB
filters: 5
filter 0: low-shelf 100 Hz +6.0 dB Q 0.70
filter 1: peak 1000 Hz -3.0 dB Q 1.00
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-eq --raw restore`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 17 02 00 00 00 ee 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 18 01 05 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 15 08 00 00 00 00 3b 00 46 01 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 01 00 00 00 b5 00 3e 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 02 00 00 02 c0 00 78 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 03 00 00 1c 03 00 96 00 00 ee 00 00 00 00
tx: aa 0a 00 00 15 08 04 00 00 0f 85 00 28 02 00 ee 00 00 00 00
tx: aa 0a 00 00 19 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: aa 0a 00 00 16 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 45 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
sent: slot: 3 (USER1)
sent: pre-gain: +0.0 dB
sent: filters: 5
sent: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
sent: filter 1: peak 181 Hz +0.0 dB Q 0.62
sent: filter 2: peak 704 Hz +0.0 dB Q 1.20
sent: filter 3: peak 7171 Hz +0.0 dB Q 1.50
sent: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
link: disconnected +0.92s
link: connected +1.82s
read: slot: 3 (USER1)
read: pre-gain: +0.0 dB
read: filters: 5
read: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
read: filter 1: peak 181 Hz +0.0 dB Q 0.62
read: filter 2: peak 704 Hz +0.0 dB Q 1.20
read: filter 3: peak 7171 Hz +0.0 dB Q 1.50
read: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
final: slot: 3 (USER1)
result: confirmed
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Step 5 notes: restore exited 0, `result: confirmed`, `final: slot: 3 (USER1)`, no `diff:` line; link away about 0.9 s again. The probe afterwards equals the baseline.

## Factory presets after

Command: `ja11-eq --raw slot vocal`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 00 5f ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 0 (Vocal)
read: slot: 0 (Vocal)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 00 5f ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 ff ed 00 28 00 64 00 a4 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 ff cf 00 b4 00 3c 00 cd ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 32 02 58 00 46 00 bf ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 3c 08 98 00 3c 00 3a ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 ff e3 1b 58 00 64 00 06 ee 00 00 00 00
state: slot: 0 (Vocal)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 40 Hz -1.9 dB Q 1.00
state: filter 1: peak 180 Hz -4.9 dB Q 0.60
state: filter 2: peak 600 Hz +5.0 dB Q 0.70
state: filter 3: peak 2200 Hz +6.0 dB Q 0.60
state: filter 4: peak 7000 Hz -2.9 dB Q 1.00
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot classic`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 01 01 ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 1 (Classic)
read: slot: 1 (Classic)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 01 01 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 ff cf 00 e6 00 64 00 50 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 19 00 50 00 64 00 fb ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 19 09 c4 00 64 00 22 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 ff e3 17 70 00 64 00 9b ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 1f 40 00 96 00 43 ee 00 00 00 00
state: slot: 1 (Classic)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 230 Hz -4.9 dB Q 1.00
state: filter 1: peak 80 Hz +2.5 dB Q 1.00
state: filter 2: peak 2500 Hz +2.5 dB Q 1.00
state: filter 3: peak 6000 Hz -2.9 dB Q 1.00
state: filter 4: peak 8000 Hz +0.0 dB Q 1.50
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot bass`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 02 e3 ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 2 (Bass)
read: slot: 2 (Bass)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 02 e3 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 1e 00 20 00 64 00 95 ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 23 00 40 00 64 00 e1 ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 19 00 64 00 64 00 78 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 19 09 c4 00 64 00 61 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 ff e3 17 70 00 64 00 4b ee 00 00 00 00
state: slot: 2 (Bass)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: peak 32 Hz +3.0 dB Q 1.00
state: filter 1: peak 64 Hz +3.5 dB Q 1.00
state: filter 2: peak 100 Hz +2.5 dB Q 1.00
state: filter 3: peak 2500 Hz +2.5 dB Q 1.00
state: filter 4: peak 6000 Hz -2.9 dB Q 1.00
result: confirmed
```
exit: 0

Command: `ja11-eq --raw slot user1`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
tx: aa 0a 00 00 16 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
sent: slot: 3 (USER1)
read: slot: 3 (USER1)
tx: bb 0b 00 00 16 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 16 01 03 bd ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 18 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 18 01 05 94 ee 00 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 17 00 00 ee 00 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 17 02 00 00 f1 ee 00 00 00 00 00 00 00 00 00 00
tx: bb 0b 00 00 15 01 00 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 00 00 00 00 3b 00 46 01 7f ee 00 00 00 00
tx: bb 0b 00 00 15 01 01 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 01 00 00 00 b5 00 3e 00 6e ee 00 00 00 00
tx: bb 0b 00 00 15 01 02 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 02 00 00 02 c0 00 78 00 30 ee 00 00 00 00
tx: bb 0b 00 00 15 01 03 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 03 00 00 1c 03 00 96 00 b5 ee 00 00 00 00
tx: bb 0b 00 00 15 01 04 00 ee 00 00 00 00 00 00 00 00 00 00 00
rx: 02 bb 0b 00 00 15 08 04 00 00 0f 85 00 28 02 e5 ee 00 00 00 00
state: slot: 3 (USER1)
state: pre-gain: +0.0 dB
state: filters: 5
state: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
state: filter 1: peak 181 Hz +0.0 dB Q 0.62
state: filter 2: peak 704 Hz +0.0 dB Q 1.20
state: filter 3: peak 7171 Hz +0.0 dB Q 1.50
state: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
result: confirmed
```
exit: 0

Factory presets after: each of vocal, classic and bass read byte-identical to its before recording (cmp on vocal/classic/bass-before.txt vs -after.txt). Because the factory slots are readable and differ from USER1, the comparison is meaningful; WRITE-04 also rests on the gate: every save frame (`aa 0a 00 00 19`) in this log carries `01 03`.

## Final state

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-probe `
```text
slot: 3 (USER1)
pre-gain: +0.0 dB
filters: 5
filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
filter 1: peak 181 Hz +0.0 dB Q 0.62
filter 2: peak 704 Hz +0.0 dB Q 1.20
filter 3: peak 7171 Hz +0.0 dB Q 1.50
filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Command: `ja11-eq backup`
```text
backup: kept /Users/dylenquyn/Library/Application Support/JA11 EQ/user1-original.json
backup-time: 2026-10-10T18:22:11Z
original: slot: 3 (USER1)
original: pre-gain: +0.0 dB
original: filters: 5
original: filter 0: low-shelf 59 Hz +0.0 dB Q 0.70
original: filter 1: peak 181 Hz +0.0 dB Q 0.62
original: filter 2: peak 704 Hz +0.0 dB Q 1.20
original: filter 3: peak 7171 Hz +0.0 dB Q 1.50
original: filter 4: high-shelf 3973 Hz +0.0 dB Q 0.40
```
exit: 0

Final state: both probes equal the baseline (slot 3 (USER1), pre-gain +0.0 dB, five filters at 59, 181, 704, 7171 and 3973 Hz, all +0.0 dB). `ja11-eq backup` prints `original:` lines equal to the baseline and `backup-time: 2026-10-10T18:22:11Z`, the same as under Step 1: the file was written once. The dongle is as it was before this plan.

## Findings (D-19)

**Re-enumeration.** Yes. After each of the three saves (identity apply, test curve, restore) the JA11 dropped off USB 0.92 s after the save frame and was back 1.82 to 1.83 s after it, away for about 0.9 s. `ja11-eq` waited this out by itself, reported it as `link: disconnected` and `link: connected` lines, and read back afterwards, so the recovery path was exercised on the real dongle (WRITE-07). No later probe found the dongle missing.

**Pre-gain scale.** The x10 scale holds. -6.0 dB was sent as `ff c4` and read back as -6.0 dB; +0.0 dB read back as +0.0 dB.

**Negative gain.** -3.0 dB (filter 1) was sent as `ff e2` and read back as -3.0 dB. The +6.0 dB of filter 0 was sent as `00 3c` and read back as +6.0 dB.

**Factory presets.** Yes: selecting a slot makes its filters readable. Vocal, Classic, Bass and Off each returned five peak filters that differ from USER1's and from one another (Off: 1000, 2000, 5000, 8000 and 10000 Hz, Q 0.70, flat). Their readings after the write and restore are byte-identical to their readings before. Pre-gain was +0.0 dB in all of them. The only save frames in the log carry `19 01 03`.

**Trailing byte.** None of six hypotheses (sum, two's complement and XOR, each over all preceding bytes or over the payload only) fits any of the eight baseline replies. The byte is not even a function of the frame content: the slot reply `16 01 03` carried `bd` in the baseline and `45` after the first save, and the other seven replies kept their bytes. SET frames with `00` in that position were accepted by the dongle on every one of the 37 SET frames sent.

**Reply to SET frames.** None. No `rx:` line directly follows any SET `tx:` line; replies only answer GET frames.

**Timing.** An apply takes about 4 s wall clock end to end (measured around the tool call): the write frames, the 0.92 s to drop-off, the dongle back at about 1.8 s, and the read-back after the settle. The dongle was away for about 0.9 s; the 1.6 s settle after the save was enough for a successful read-back in all three saves.

**Not examined in this phase.** Whether a filter write is audible before the save (v2 CONV-02), and whether the on-board EQ is active at 352.8 kHz, which only the audible check can show (v2 CONV-04).
