# OneBuds feature record

This file records, for each feature, the protocol bytes, the expected response, how it is verified, and what has been tested on which hardware. Byte layouts are described in [ProtocolSources.md](ProtocolSources.md) §4–§6.

**Frame notation:** `AA <len> 00 00 <cmd LE> <seq> <paylen LE> <payload>`. Below, only the command and payload are shown.

**Status keys** (Verified here means the owner asked for the test and the earbuds acknowledged and read back every change; whether you could *hear* the change is still for you to confirm):

- **Verified:** the owner tested it on hardware and confirmed the result.
- **Observed:** the earbuds answered on the owner's hardware with the documented layout, but the owner has not yet confirmed the values.
- **Experimental:** implemented from documentation and tested only against the simulator.

**Test device:** owner's OnePlus Buds 3, product ID `063C14`, firmware **127.127.101**. Transport: RFCOMM channel 15 (`"enco link"`, SDP `0000079A-…`) on macOS 15.7.3. Captured on 2026-10-12. Replies are kept as test fixtures in `Tests/OneBudsCoreTests` (`CapturedBuds3Fixtures`).

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

**Not implemented:**

- Custom EQ curves
- Find my earbuds (plays a loud sound)
- Spatial audio
- Hi-Res
- Power saving
- Firmware update
- Factory reset
- Any command absent from the model profile
