# OneBuds feature record

This file records, for each feature, the protocol bytes, the expected response, how it is verified, and what has been tested on which hardware. Byte layouts are described in [ProtocolSources.md](ProtocolSources.md) §4–§6.

**Frame notation:** `AA <len> 00 00 <cmd LE> <seq> <paylen LE> <payload>`. Below, only the command and payload are shown.

**Status keys** (Verified here means the owner asked for the test and the earbuds acknowledged and read back every change; whether you could *hear* the change is still for you to confirm):

- **Verified:** the owner tested it on hardware and confirmed the result.
- **Observed:** the earbuds answered on the owner's hardware with the documented layout, but the owner has not yet confirmed the values.
- **Experimental:** implemented from documentation and tested only against the simulator.

**Test device:** owner's OnePlus Buds 3, product ID `063C14`, firmware **127.127.101**. Transport: RFCOMM channel 15 (`"enco link"`, SDP `0000079A-…`) on macOS 15.7.3. Captured on 2026-10-12. The same feature test passed over BLE GATT (`0100`/`0200079A`) on 2026-11-03; OneBuds now tries GATT first and falls back to RFCOMM (Settings ▸ General ▸ Connection). Replies are kept as test fixtures in `Tests/OneBudsCoreTests` (`CapturedBuds3Fixtures`).

| Feature | Request | Expected reply | Verification method | OnePlus Buds 3 (fw 127.127.101) | Limitations |
|---|---|---|---|---|---|
| Session handshake | `0x0100` (empty) | `0x8100`: `00` + capability bitmap | Reply arrives and decodes | **Observed:** `00 FF 77 5A EE E7 0E 22 00` (35 bits set) | Bit meanings come from S5's table and are not verified |
| Model identification | `0x0103` | `0x8103`: `00 <id 3 bytes LE>` | Product ID matches the profile, otherwise the session stops | **Observed:** `00 14 3C 06` = `063C14` | — |
| Renamed buds | Passive BLE scan: OPPO manufacturer data `9A 07 <product id LE> … <classic address>` | — | Matches the advertisement to the connected classic device by address; the result is cached under an address hash | **Experimental:** unit-tested; live runs connected under the stock name | Needs the buds to be advertising |
| Firmware | `0x0105` | `0x8105`: `00 <n>` + `type,versionType,version` triples | Parse plus display | **Observed:** 5 triples, shown as `127.127.101` | The display rule (join versionType-2 values) is from S4 |
| Time reply | buds send `0x0500` | host sends `0x8500` `00 <unix u32 LE>`, echoing seq | Unit test reproduces S1's "token" bytes | **Not observed:** Buds 3 sent no `0x0500` in two sessions | Answered only if the buds ask |
| Event subscription | `0x0200`, then `0x0205 <n> <ids>` | `0x8200`: `00 <n> <ids>`; `0x8205` | Reply arrives | **Observed:** offered `01 02 03 04 08 0B F1 F2 F3`; subscribed to the 6 ids below 0xF0. The reply `01 06 01 00 02 00 …` starts with `01` rather than `00` (meaning unknown; it is not checked). | — |
| Battery | `0x0106` | `0x8106`: `00 <n> [<idx> <raw>]…`; idx 1 = L, 2 = R, 3 = case; `raw & 0x7F` = %, `raw & 0x80` = charging. Push: `0x0204 01 …` | Read on connect; pushes merge | **Observed:** `03 01 64 02 64 03 64` = 100/100/100 (buds in the open case). Values not yet confirmed against the phone. | Level 0 means unknown; the case is omitted when its lid is closed |
| Wear status | push `0x0204 02 <n> [<comp> <status>]…` | — | Event decoded | **Observed:** `02 03 01 04 02 04 03 04` = all in case, lid open (status bit 2) | Status bits from S4 |
| Noise control: read | `0x010C 01 01` | `0x810C`: `00 01 01 <LO> <HI>`. Values: `0x0008` Off, `0x0100` Transparency, `0x0002`/`0x0010`/`0x0020`/`0x0040`/`0x0080` ANC (generic/Deep/Medium/Light/Smart) | Read on connect; push `0x0204 03 01 01 LO HI` | **Observed:** `00 01 01 08 00` = Off | Level values are a hypothesis (C2) |
| Noise control: set | `0x0404 01 01 <mask>`. Masks: Off `01`, ANC `02`, Transparency `04`, Deep `10`, Medium `20`, Light `40`, Smart `80` | `0x8404 00`, then a **read-back** must match | The UI changes only after the read-back. Status `0E` means no bud in an ear. | **Verified 2026-10-12:** all 7 modes acknowledged (`8404 00`), read back correctly, and pushed as `0x0204 03 01 01 LO HI` | Needs a bud in an ear |
| Equalizer | Read `0x010F` → `00 <id>`. Set `0x0406 <id>` → `00`, then read-back | Preset IDs: 0 Balanced, 1 Deep Sea Bass, 2 Pure Vocals, 3 Bright & Crisp (fw ≥ 119) | Read-back | **Verified:** presets 0–3 set and read back; push `0x0504 <id>` observed | No custom EQ curves |
| Game mode / in-ear detection / dual connection | Read `0x010D <n> <ids>` → `00 <n> [<id> <v>]…`. Set `0x0403 <id> <0/1>` → `00`, then read-back | IDs: `06` game, `04` wear, `11` dual | Read-back | **Verified:** game mode `06` set on/off and read back. In-ear `04` toggles and is confirmed, but its *effect* is unconfirmed (Experimental). Dual `11`: read only (Experimental). | IDs `17` (restarts the buds) and `18` (drops the link) are never writable |
| Touch gestures | Read `0x0108` → `00 <n> [<side> <btn> <act> <fn>]…`. Set `0x0401 <n> [entries]` → `00`, then read-back | Functions are limited to the profile's per-action list | Read-back | **Observed read:** 12 entries (per earbud: single, double, triple, hold, long-hold and slide). Double tap = `06` (next), triple tap = `05` (previous). **Verified:** left double tap set to Voice assistant and restored, both read back. | Long-hold and call gestures are not editable |
| Multi-device list | push `0x0204 06 …` | Contains other devices' addresses and names | — | **Observed** unsolicited on connect | **Always redacted** in logs and exports, and never displayed |
| Wear read | `0x0109` | `[00] <n> [<comp> <status>]…` | Read once on connect if no push arrived yet | **Experimental:** bitmap bit 4 set; never queried yet | Read only |
| Custom EQ | Read `0x0122` → `00 <n>` + per preset `<sel> <min> <max> <id> <len> <name> <n> [<freq LE16> <gain>]…`. Write `0x0418 <1 create/2 save/3 delete> <-max> <max> <id> <len> <name> <n> <bands>` | `00`, then the list is read back | Create: a new id with the name appears (ids are renumbered). Save: the gains match. Delete: one fewer, the name is gone. Built-in ids are refused. | **Experimental:** bitmap bit 34 set; untested on Buds 3. Band layout copied from presets already on the buds, else S4's Buds 4 layout (62 Hz–16 kHz, ±6 dB, 3 presets) | Names are 1–16 ASCII characters |
| BassWave | Switch `0x1D`; strength read `0x0124` → `00 FB 05 <s8>`, set `0x041B FB 05 <s8>` (−5…+5) | `00`, then read-back | Read-back | **Experimental:** bitmap bit 38 set; untested | — |
| 3D audio / smart volume | Switches `0x1B` / `0x1C` | `00`, then read-back | Read-back | **Experimental:** listed for Buds 3 in S4; untested | Hi-Res `0x18` stays never writable |
| Noise-control cycle | Read `0x010C 02 01` → `00 02 01 <mask>`; set `0x0404 02 01 <mask>`. Bits: Off 0, ANC 1, Transparency 2 | `00`, then read-back; push `0x0204 03 02 01 <mask>` | Read-back | **Experimental:** bitmap bit 8 set; the `02 01` read was never sent to Buds 3 | At least one mode stays selected |
| Call controls | Gesture entries with side `04`, button `06`: double tap `00`/`1D` answer–end, long hold `00`/`1C` decline | `00`, then gesture read-back | Read-back | **Experimental:** Buds 3's table had no call entries on 127.127.101, so the section stays hidden there | — |
| Find my earbuds | `0x0400 01` start, `0x0400 00` stop | `00` | Acknowledgement only (no state to read) | **Experimental:** bitmap bit 5 set; untested | Loud. Only on a click, with a warning next to the button |
| Fit test | `0x0405 01`, result push `0x0204 04 [<side> <status>]…` (1 good, 0 average, 6 poor), then `0x0405 00` | `00` + push within 15 s | The push itself is the result | **Experimental:** bitmap bit 9 set; event `04` offered and subscribed | Needs both buds in |
| Golden Sound hearing test | Start `0x040D 02 01`; tone `0x040E 03 01 <side> <freq> <level>`, stop `0x040E 04`; filter `0x0116 0C <36 bytes> <uid BE32>`; restore `0x0411 01 01 01 00 <type>`; store `0x040E 03 0C <36 bytes> <uid> <name>`; read `0x0115`; switch `0x0B` on; end `0x040D 02 00` | `00` per step; status pushes `0x0204 08 <kind> <status>` | The stored profile is read back (uid and values must match), then the switch | **Experimental:** bitmap bits 19 and 25 set; untested. Sequence from S4 section 20 | Tones start quiet and never go above level +10 |

**Mac-side features** (no earbud protocol): the output-volume slider (CoreAudio, default output device) and low-battery notifications (UserNotifications; once per crossing, re-armed 5% above the threshold or when charging).

**Not implemented:**

- Hi-Res
- Power saving
- Firmware update
- Factory reset
- Any command absent from the model profile
