# BMW E90 / E8x / E9x K-CAN DBC — Mega Merge

A merged and extended DBC file for BMW E90, E8x, and E9x platforms covering the K-CAN bus.

Built by combining the best available community DBC sources and extending them with empirically
captured signal definitions from real vehicle and HIL (Hardware-in-the-Loop) bench testing.

---

## File

| File | Description |
|---|---|
| `bmw_e9x_e8x1_merged.dbc` | Merged DBC — all sources combined with our own additions |

---

## What Was Added

Signal definitions and message comments added beyond the source material:

- **Central locking (0x2A0)** — `LockCmd_B0/B1/B2`: lock, unlock, trunk open command bytes (empirical)
- **Windows (0x3B6–0x3B9)** — `WindowMovement`: per-door open/moving/closed state
- **Interior lighting (0x2FA / 0x2FC)** — FZD lamp states and door/boot/bonnet open bitmask
- **Wiper switch (0x2A6)** — `WiperSpeedMode`, `WiperAutoActive` from SZL stalk
- **Wiper status (0x252)** — `WiperStatus`: parked / going up
- **Climate (0x2D5, 0x2D6, 0x34F)** — rear window heater, AC compressor, AC status
- **Handbrake (0x34F)** — `Handbrake_pushed_down`, `Handbrake_pulled_up`
- **Gear display (0x304)** — `GearDisplay` with named enum values
- **Reverse gear (0x3B0)** — `ReverseGear_3B0`
- **Ambient temperature (0x2CA)** — decode formula confirmed from HIL capture
- **Seatbelt indicator (0x581)** — ACSM byte 3 provisional mapping
- All signal comments include source attribution and decode notes

---

## Sources and Attribution

This DBC is derived from and extends the following sources:

### GitHub Repositories
- **[opendbc-BMW-E8x-E9x](https://github.com/dzid26/opendbc-BMW-E8x-E9x)** by dzid26 — primary base (MIT)
- **[canbus](https://github.com/nberlette/canbus)** by nberlette — additional E90 signals
- **[E65_ReverseEngineering](https://github.com/HeinrichG-V12/E65_ReverseEngineering)** by HeinrichG-V12

### Websites and Forums
- **[loopybunny.co.uk/CarPC](https://www.loopybunny.co.uk/CarPC/)** — extensive E90 K-CAN signal reference
  (speed, doors, climate, iDrive, indicators, wiper status, GPS, VIN and more)
- **[bimmerforums.com](https://www.bimmerforums.com/forum/showthread.php?2298830-E90-Can-bus-project-(E60-E65-E87-)&p=29628499#post29628499)** — E90 CAN bus Tool32 reference thread
- **[m5board.com](https://www.m5board.com/posts/7693749/)** — MK60e5_Development_DBC.dbc
- **rusefi.com** — BMW E65 Tool32 K-CAN table (navigation messages)

### Unlinked References
- **MorGuux E90 K-CAN gist** — network management frames and gear selector
- **MSD81 document** — engine control module data

---

## License

MIT — see [LICENSE](LICENSE).

Derivative work based on [opendbc-BMW-E8x-E9x](https://github.com/dzid26/opendbc-BMW-E8x-E9x) (MIT).
Original copyright remains with respective authors.
