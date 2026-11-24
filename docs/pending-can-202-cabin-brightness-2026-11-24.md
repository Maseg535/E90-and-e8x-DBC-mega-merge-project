# Pending DBC update: CAN 0x202 cabin brightness (2026-11-24)

# BMW E90 LCI: cabin dimming via K-CAN 0x202 (verified 2026-11-24)

## Vehicle and evidence
BMW E90 LCI, 03/2011, CIC. Source: real-vehicle capture `idrive-can-capture-20261124-102146.log.txt` (2026-11-24), manual adjustment of instrument-cluster lighting setting from high to low and back. Owner visually verified that all ordinary cabin illumination, including CIC and IHKA controls, changes synchronously. This is **not merely a guessed ID association**.

## Frame
CAN ID: 0x202 (decimal 514); DLC 2; payload `XX FF`.
Observed ordered 8-level scale for byte 0: `00`, `24`, `48`, `6C`, `91`, `B5`, `D9`, `FD` (decimal 0,36,72,108,145,181,217,253). Minimum 00; maximum FD. Byte 1 always FF in this recording. Intermediate levels repeat and are stable. Approximate normalized position may be computed as index/7, but the actual light-output curve is not measured.

Samples: `2005349 202 2 D9 FF`, `2012698 202 2 00 FF`, `2020149 202 2 FD FF`, `2025408 202 2 6C FF`. Capture starts at level D9, descends to 00, rises to FD, then returns to 6C.

## Confirmed vs unknown
- Confirmed: settings are adjusted via the instrument cluster; 0x202 follows selected brightness; visible cabin illumination changes synchronously.
- Exceptions noticed visually: LEDs in SZL and rear overhead module's tunnel illumination appear to stay at maximum. Exact circuit/control mechanism unknown.
- Original E90 steering-wheel illumination control **not confirmed**. In the current retrofitted wheel, its lighting does not change with the cluster setting. Do **not** infer that all OEM wheels lack dimming.
- Transmitter ECU, CAN-injection authority and whether 0x202 alone actuates consumers have **not** been independently verified. Do not transmit conflicting frames on a live vehicle to test without a controlled plan.

## Integration requirement: F30 steering-wheel LIN module
The custom F30 LIN wheel backlight **must follow the same cluster brightness setting** instead of remaining fixed:
1. Listen for valid 0x202 DLC=2 frames; accept only the eight confirmed B0 values initially; B1=FF is the observed baseline. No CAN transmission is needed.
2. Translate the eight discrete levels to the verified LIN brightness-control behavior (existing wheel module already supports nonzero brightness commands). Calibrate actual LIN duty/brightness mapping on hardware; do not assume identical linear transfer functions between 0x202 and LIN.
3. Preserve safe fallback at CAN startup, loss of brightness messages and sleep/wake; keep brightness separate from illumination enable/on/off, and never force the LEDs on merely because the last level is nonzero.
4. Test each of the 8 levels with a stationary vehicle, checking monotonicity, min/max, no flicker, and calibrating the minimum **visible** LIN brightness; do not use 00 as an automatic power-off command.
5. Firmware must not change until the corresponding module implementation is planned/tested; this file documents the confirmed contract and requirement, not an implementation.

## DBC backlog
Add or refine CAN ID 0x202 (decimal 514), DLC=2: an 8-bit unsigned `CabinIlluminationLevelRaw` at start bit 0, length 8, little-endian (`0|8@1+`, factor 1), value table 0/36/72/108/145/181/217/253 -> levels 0..7; second byte 0xFF observed constant/reserved (do not label checksum). Check the existing ID 514 declaration **before** editing; preserve its sender and existing signals unless evidence warrants changes. Add CM_ traceability and a parser/DBC validation check. Coordinate update of canonical `Maseg535/E90-and-e8x-DBC-mega-merge-project/bmw_e9x_e8x1_merged.dbc` and synchronized copy in `IDRIVE_NEW/dbc/`, plus clients that bundle a DBC (Android). Do not mark DBC task done until both are synced and tested.

**Status:** documentation/queued only; DBC file not changed as part of this note.


## Additional direct ZBE/iDrive joystick test (2026-11-24)
The owner separately injected CAN 0x202 for **the iDrive joystick only**:
- `00 FF` = minimum **visible**, nonzero illumination.
- `FE FF` = visually same minimum illumination as `00 FF`.
- `FF FF` = ignored (no visible brightness change).
These are **joystick-only** results, not verified for all other lighting consumers, and `FE` is not one of the 8 cluster-selected levels. The reason FE aliases minimum and FF is ignored is unknown (special encoding, bounds/wrap, validity sentinel, etc. are hypotheses only). Keep the observed normal cluster 8-level table separate from the joystick edge-case table. For future firmware, do not interpret B0=00 as backlight OFF; keep on/off state separate from minimum dimming, and never extrapolate FE/FF behavior to the wheel LIN module without tests. DBC may record FE/FF as ZBE-specific observed edge cases in a comment, without declaring these standard brightness levels.
