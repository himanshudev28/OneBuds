# OneBuds: Protocol Sources and Provenance

Status: **Phase A (research)**. Last updated 2026-10-12.

This document records every protocol fact OneBuds relies on, where it came from, and how sure we are of it. Code in OneBuds is written independently from these facts. No source code from any reference project is copied (see §2).

## Labels

| Label | Meaning |
|---|---|
| **Documented** | Stated by a cited source (code, docs, capture, or issue). Not yet tested by OneBuds. |
| **Verified** | Tested by the OneBuds owner on physical hardware. Each entry records the date, model, and firmware. |
| **Hypothesis** | Our own inference from documented facts. It must be tested before the app relies on it. |

At the end of Phase A, **nothing is Verified**. No OnePlus Buds 3 traffic has been captured anywhere we found.

Phase B (2026-10-12) added **Observed** facts from your Buds 3: service records and GATT layout (§4 of [PhaseB-Report.md](PhaseB-Report.md)). It also added owner-approved query traffic over RFCOMM channel 15, which answered the handshake, product ID, firmware, battery and every read (§6 of the same report, and [Features.md](Features.md)). No setting change has been sent yet.

---

## 1. Source register

Commit SHAs pin the exact revision that was read.

| ID | Source | Licence (confirmed) | Revision read | Reuse policy |
|---|---|---|---|---|
| S1 | [vedanth-jadhav/open-oneplus-buds](https://github.com/vedanth-jadhav/open-oneplus-buds) (SwiftPM menu-bar app, BLE) | README says "MIT". **No LICENSE file and no copyright line.** GitHub reports `license: null`. | `main` @ `0d6695918a2b9455df5973f755dd88ada04f359f` (2026-03-13) | Facts only. Code is not copied, because the MIT notice the licence requires does not exist. Credited. |
| S2 | [AasheeshLikePanner/cracked-oneplus-buds](https://github.com/AasheeshLikePanner/cracked-oneplus-buds) (original OPOv1 BLE research) | README says "MIT". **No LICENSE file and no copyright line.** | `main` @ `632076540684a2127ef701db9e3c9a309ffac8fb` (2026-02-27) | Facts only. Credited. |
| S3 | [aasheesh.vercel.app/blog/oneplus-buds](https://aasheesh.vercel.app/blog/oneplus-buds) (write-up, "© 2026 Aasheesh Rathour") | No licence stated | Fetched 2026-10-12 | Cited as a source |
| S4 | [spizganed/QuickBuds](https://github.com/spizganed/QuickBuds) (`docs/PROTOCOL.md`, Android/desktop, RFCOMM) | **GPL-3.0-or-later**, © 2026 spizganed | `main` @ `47929f34d52e29b69e37b95bfbd74df0813ca240` (2026-10-11) | **Read only.** Facts only, re-implemented independently. |
| S5 | [Zhaoyi-ya/OppoPodsManager](https://github.com/Zhaoyi-ya/OppoPodsManager) (Windows/Linux, 137 models; **archived** 2026-09-30) | **GPL-3.0-or-later**, © 2026 Zhaoyi-ya | `main` @ `96eddba02a666907e8583613cfc3461206808fba` (2026-09-30) | **Read only.** Facts only. Its `DeviceModels.json` derives from HeyMelody's model list and is **not** bundled in OneBuds. |
| S6 | [noctalia oppo-pods](https://noctalia.dev/plugins/community/oppo-pods) → upstream [osp54/oppo-pods](https://github.com/osp54/oppo-pods) | **MIT**, © 2026 osp54 | `main` @ `3dbdc475b3fcdb003c6e052eb4c8ee74345ea700` (2026-09-05) | Low trust (see §7). Its embedded HeyMelody server secret and cloud calls must **not** be reused. |
| S7 | [1812z/OppoPods](https://github.com/1812z/oppopods) (Android/HyperOS), a fork of Leaf-lsgtky/OppoPods, derived from Art-Chen/HyperPods (GPL-3.0) | README says GPL-3.0. **No LICENSE file.** | `master` @ `c201e251e68b59d46b6bc2758146b2c7f13ca2a1` (2026-10-04) | **Read only.** Facts only. |
| S8 | Leaf-lsgtky/OppoPods `docs/HeyMelody_*` notes (decompiled HeyMelody findings) | No LICENSE file | Read 2026-10-12 | Facts only. Cross-reference for UUIDs and framing. |
| S9 | OOB fork ShubhamJ010/open-oneplus-buds, PR #1 (Buds Z2 notes) | No licence | `docs/buds-z2-protocol-notes` @ `0aa2aee916be2c642f1e5538903c4f74ad9a491b` | Low confidence: the PR says it was researched with an AI tool. |
| S10 | [kunalagra/OtoControl](https://github.com/kunalagra/OtoControl) (web app, Web Serial / RFCOMM, 137-model catalogue) | README says "AGPL-3". **No LICENSE file.** | `main` @ `90bdd977b7d49070e83e7c50a4dd4cfce8681129` (2026-10-04) | **Read only.** Facts only. |
| S11 | [digisatapathy2025/oneplus-buds-mac](https://github.com/digisatapathy2025/oneplus-buds-mac) (Python + Swift, BLE GATT) | **No licence** ("personal and educational use") | `main` @ `1832204a888d6b3a367cf722beb440a09241b605` (2026-09-13) | **Read only.** Facts only. Its repo contains vendor cloud secrets extracted from HeyMelody; **never use them.** |
| S12 | [Zeno-cc/OPPO-Earbuds-Mac-Controller](https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller) (Swift, IOBluetooth RFCOMM, hardware-tested on OPPO Enco Air5 Pro, T500 Pro, Free4) | **MIT**, "Copyright (c) 2026 Aniket Budhwani" (LICENSE file present) | `main` @ `2fe01696c8df2194f09d630373c5acd9b743a382` (2026-09-30) | **Reusable with attribution.** Preferred reference for `RFCOMMTransport`. Sparkle is not adopted. |
| S13 | [timschneeb/GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient) | **GPL-3.0**, © 2021 Tim Schneeberger | `master` @ `754b6fdfb1c151b022cece775c8aaad4eb185afa` (2026-10-01) | **Read only.** Architecture ideas and IOBluetooth pitfalls. |
| S14 | [vedatkilic/galaxy-buds-mac](https://github.com/vedatkilic/galaxy-buds-mac) (Swift 6, IOBluetooth RFCOMM) | **MIT**, "Copyright (c) 2026 Vedat Kılıç" | `main` @ `3ffedf8217695075188ac4a6b1d0664022f58d92` (2026-09-06) | **Reusable with attribution.** Release notes record macOS lessons. |
| S15 | Gadgetbridge ([codeberg.org/Freeyourgadget/Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge)) OPPO/realme support and its BT reverse-engineering guide (now at gadgetbridge.org/internals/development/bluetooth/) | **AGPL-3.0** | `master` @ `862ec6cb4ed40dbb484a2655de64b91444f43773` (2026-10-11) | **Read only.** Facts and the capture procedure. It has no OnePlus models. |

### Credits

The OPOv1 BLE research is by **Aasheesh (Rathour)** (S2, S3). The first Swift menu-bar implementation is by **Vedanth Jadhav** (S1). The RFCOMM protocol documentation and the model data are by **spizganed** (S4), **Zhaoyi-ya** (S5), and the OppoPods authors (S7, S8).

---

## 2. Licence conclusions

1. **Only S12 and S14 (and S6) have a valid permissive licence.**
   - S12 and S14 are MIT with LICENSE files. OneBuds may adapt their code. Any adapted file keeps the MIT notice in its header and is listed in `THIRD_PARTY_NOTICES.md` and in §10.
   - S1 and S2 claim MIT but ship no licence text or copyright notice. MIT's only condition is to keep that notice, so there is nothing valid to keep. (Not legal advice.)
   - S4, S5, S7, S10, S11, S13 and S15 are GPL, AGPL, or unlicensed.
   - S6 is properly MIT, but it is a Python script of low quality.
2. **The protocol layer is clean-room.** Protocol facts (UUIDs, command IDs, byte layouts, model parameters) are recorded here with their source. The Swift code is written from these tables, not from reference code.
3. **Optional follow-up for you:** ask S1 and S2 to add a LICENSE file. If they do, re-pin the SHAs above. Nothing in the plan depends on it.
4. **We will not bundle the HeyMelody model database** (S5's `DeviceModels.json`). The registry only gets entries we write by hand for models we have worked on.

---

## 3. Transports

A single protocol runs over two different Bluetooth links (S4, S5, S7, S8, matched against S1 and S2).

| Fact | Value | Label | Source |
|---|---|---|---|
| RFCOMM SDP service UUID (current models) | `0000079A-D102-11E1-9B23-00025B00A5A5` | Documented | S4 `OpoProtocol.kt` L21-22; S5 `OppoManagerFactory.cs` L12-13; S7 `RfcommController.kt` L104 |
| RFCOMM SDP service UUID (older models) | `00001107-D102-11E1-9B23-00025B00A5A5` | Documented | S4; S8 |
| RFCOMM channel numbers | Must come from SDP. Never hard-code (observed values 15 for 079A and 5 for 1107 are measurements, not constants). | Documented | S4 PROTOCOL.md L22-29; S8 |
| BLE GATT service | `0000079A-D102-11E1-9B23-00025B00A5A5` | Documented | S1 `OPOProtocol.swift` L4; S2 `nordbuds.swift` L40; S8 ("SPP over GATT") |
| BLE write characteristic | `0100079A-D102-11E1-9B23-00025B00A5A5`, **write without response** (with-response writes silently do nothing) | Documented | S1 L5; S2 L87, README L42-48; S3 Part 4; S8 |
| BLE notify characteristic | `0200079A-D102-11E1-9B23-00025B00A5A5` | Documented | S1 L6; S2 L92; S8 |
| `FE2C` | S2 and S3 say responses also arrive on the "FE2C" service. 0xFE2C is the Google Fast Pair service, and `FE2C1234-…` is its Key-based Pairing characteristic. | Hypothesis: FE2C is Fast Pair, not part of OPO. Phase B will check whether anything OPO-shaped arrives there. | S2 README L59-63; S3 Part 5 |
| `0000079C-…A5A5` service | S1 skips it because it "can require encryption and disconnect". | Documented | S1 `BudsClient.swift` L754-770 |
| Alternate GATT UUIDs (`0000079B`/`079C`, `DF21FE2C-2515-4FDB-8886-F12C4D67927C` family) | Listed by S5 for some OPPO models. They conflict with S8's write `0100079A` / notify `0200079A`. | Documented for other models; not used for OnePlus | S5 `LinuxGattConnection.cs` L40-60 |
| OnePlus Buds 3 bearer | The HeyMelody model list gives UUID `0000079A…` and `supportSpp: true`. | Documented (model list) | S5 `DeviceModels.json` L11705-11873; S7 `device_models.json`; S10 `catalog.generated.ts` L149 |
| OnePlus Buds 3 over BLE GATT from macOS | S11 claims a hardware "Pass" on "OnePlus Buds 3 (E509A, 063C14)" over the 079A GATT service on macOS 15. Its PacketLogger traces are not published. | Documented (unverified claim) | S11 `PROGRESS_2026-09-13.md` L42-47 |
| Same-generation OPPO over RFCOMM from macOS | S12 opens the 079A SDP service (SDP name `oppointeraction`) over IOBluetooth RFCOMM on the Enco Air5 Pro, whose noise-control tree is identical to Buds 3's. | Documented (hardware-tested by S12) | S12 `docs/PROTOCOL.md` L7-13, `docs/ARCHITECTURE.md` L31 |

---

## 4. Frame format ("OPOv1" / HeyMelody headset protocol)

The layout is the same on both bearers. There is **no checksum, CRC or footer** (S3 Part 6; S4; S5; S8).

| Offset | Field | Notes | Label | Source |
|---|---|---|---|---|
| 0 | `AA` | Start of frame | Documented | all |
| 1 | Length | Bytes after this field, i.e. `7 + payloadLen`. Encoded as a 7-bit little-endian varint (LEB128): a 124-byte payload gives `AA 83 01`. | Documented | S4 PROTOCOL.md L35-64; S8 |
| 2 | Control/FSN | `00` when unfragmented. The low 2 bits may signal fragmentation. | Documented | S8 |
| 3 | Reserved | `00` | Documented | S4 |
| 4–5 | Command, u16 little-endian | High byte is the group: `01` query, `02` notification/subscribe, `04` set, `05` request from the buds, `0F` misc. | Documented | S4; S5 `FrameCodec.cs` L11-31 |
| 6 | Sequence | Replies echo it. `FF` marks an unsolicited push. | Documented | S4 |
| 7–8 | Payload length, u16 little-endian | | Documented | S4; S5 |
| 9… | Payload | Replies to queries and sets begin with a status byte; `00` = OK. | Documented | S4 |

- A reply's command is the request's command `| 0x8000`, e.g. `0x0106` → `0x8106`.
- One BLE notification can carry several concatenated `AA` frames (S9). The decoder must split them on the length field, and must buffer partial frames across notifications and RFCOMM reads.
- **Correction to S2 and S3:** their docs call byte 1 "length from CAT", byte 6 "SEQ (+2)" and byte 7 "FLAG 03". Every frame in S1 and S2 fits the layout above instead: byte 7 is the payload length. Label: Hypothesis, but consistent with all fixtures.

---

## 5. Session start

| Step | Bytes / behaviour | Label | Source |
|---|---|---|---|
| Handshake | Command `0x0100`, empty payload: `AA 07 00 00 00 01 <seq> 00 00` | Documented | S4 L60-64; S1 L13-15 (S1 has a stray trailing `12`) |
| **Time request from the buds** | The buds send `0x0500`. The host must reply `0x8500`, echo the seq, with payload `00 <current Unix seconds, u32 LE>`. **Nord Buds 3 Pro drops the link 3–5 s after connect if this goes unanswered.** | Documented | S4 PROTOCOL.md L722-745 and issue #2 |
| **The "auth token" `B5 50 A0 69`** | S1 and S2 send `AA 0C 00 00 00 85 41 05 00 00 B5 50 A0 69`. Decoded under §4, that is command `0x8500` (the time answer) with payload `00` + u32 LE `0x69A050B5` = 1772114101 = **2026-02-26 13:55:01 UTC**, the day before S2 was created. It is a time reply copied from one capture, not authentication. | Hypothesis (strong; the arithmetic was checked by hand) | Derived from S1 L11-19, S3 Part 8, S4 |
| Product ID | Query `0x0103` → `00 <3 bytes LE>` | Documented | S4 L169-171; S5 `DeviceInfoManager.cs` L21-39 |
| Capability bitmap | `0x8100` (handshake reply) payload is `00` + an LSB-first bitmap that gates commands. The bit table is in S5 `CapabilityReader.cs` L60-113. | Documented | S4 L163-168; S5 |
| Event subscription | Query `0x0200` → `00 <count> <event ids>`. Then subscribe with `0x0205 <count> <ids>`, or use `0x0201 <id>` per event when capability bit 22 is absent. | Documented | S4 L205-243 |
| Other requests from the buds that need answers | `0x050C` → `00 01 00`; `0x051C` → `00 00 00`; `0x051D` → `01`; `0x0204` push `F2` → `00 F2`; unknown → `01` | Documented | S4 L722-745 |
| S1's "ANC query" `AA 09 00 00 04 82 44 02 00 00 F2` | Decodes as `0x8204` ack `00 F2`, an acknowledgement to the buds, **not** a query | Hypothesis | S1 L21-24 decoded with §4 |
| Recommended init order | Handshake, product ID, event list, subscribe, features, ANC, battery, wear, gestures, about 200 ms apart. After that, rely on pushes and do not poll. | Documented (captured on OnePlus Buds 4) | S4 L148-159 |

**Consequence for OneBuds:** model profiles carry no "auth token". The session layer answers `0x0500` with the real time.

---

## 6. Commands

All entries are **Documented**. None are verified on OnePlus Buds 3.

| Feature | Request | Reply / push | Notes | Source |
|---|---|---|---|---|
| Battery | `0x0106` | Reply `00 <n> [<idx> <raw>]…`; push event `01` with the same body | idx `01` = L, `02` = R, `03` = case. Level = `raw & 0x7F`; charging = `raw & 0x80`. Level 0 means unknown. The case is omitted when the lid is closed. | S4 L459-469; S5 `Battery.cs` |
| Firmware | `0x0105` | `00 <n>` + UTF-8 `type,versionType,version` triples | S1 calls this "EQ query" and parses it as EQ. That is wrong. | S4 L177-180 |
| ANC read | `0x010C 01 01` | `00 01 01 <LO> <HI>`; push `03 01 01 <LO> <HI>` | Read values: `0x0008` Off, `0x0002` ANC, `0x0010`/`20`/`40`/`80` Deep/Medium/Light/Smart, `0x0100` Transparency, `0x0800` Adaptive | S4 L291-317 |
| ANC set | `0x0404 01 01 <mask>` | Ack `8404 00`. Status `0E` = refused because no bud is in an ear. | Mask = `1 << protocolIndex`. The set bits **differ from** the read bits. | S4 L273-289; S5 `OppoManager.cs` L1165-1172 |
| Wear | `0x0109` | `<n> [<component> <status>]…`; push event `02` | bit 0 = out of case, bit 1 = in ear, bit 2 = lid open | S4 L471-489 |
| Feature switches | `0x0403 <id> <01/00>`; read with `0x010D <n> <ids>` | `00 <n> [<id> <val>]…` | Ids: `04` wear detection, `06` game mode, `11` dual connection. Only send ids from the model's own list. **`17` power saving restarts the buds and `18` Hi-Res drops the link.** | S4 L495-546 |
| EQ | Select `0x0406 <id>`; read `0x010F`; push `0x0504 <id>` | | Preset ids are per model | S4 L658-689 |
| Gestures | Read `0x0108`; write `0x0401` | 4-byte entries `[dev, btn, act, fn]` | `0x0402` is silently ignored | S4 L349-455 |
| Codec | `0x0114` | `00 <codec>` | | S4 L645-656 |
| Find buds | `0x0400 01/00` | | Plays a loud sound. User-initiated only. | S4 L184-203 |

**Never sent by OneBuds:** firmware update, factory reset, power-saving (`17`), and any command not in the model profile.

---

## 7. Model facts

### OnePlus Buds 3 (user's hardware)

| Field | Value | Label | Source |
|---|---|---|---|
| Product ID | `063C14` (an `0x8103` reply would read `00 14 3C 06`) | Documented (model list); the reply bytes are a Hypothesis | S5 `DeviceModels.json` L11705-11873; S7 (identical entry) |
| Service UUID | `0000079A-…`, `supportSpp: true` | Documented | same |
| ANC modes | Off (index 0), Transparency (2), ANC with Smart (7) / Deep (4) / Medium (5) / Light (6). **No Adaptive.** | Documented | same |
| ANC set values (`0x0404 01 01 <v>`) | Off `01`, ANC with no level `02`, Transparency `04`, Deep `10`, Medium `20`, Light `40`, Smart `80`. Read-back: Off `0x0008`, Transparency `0x0100`, levels `0x0010`–`0x0080`. | Hypothesis: from S4's set table and S12's values verified on the Air5 Pro, which has an identical tree. **S11 disagrees on the level bits.** Test on hardware first. | S4 L273-317; S12 `DeviceProfile.swift` L103-181; S11 `protocol.py` L59-116 |
| Model number | E509A | Documented (S11 only) | S11 |
| Feature-status ids | `05 04 0B 11 18 06 1B 1D 1C` | Documented | same |
| EQ presets | 0 Balanced, 1 Deep Sea Bass, 2 Pure Vocals, plus 3 Bright & Crisp on firmware ≥ 119. Custom EQ supported. | Documented | S5 |
| Confirmed working anywhere? | QuickBuds says "Not confirmed yet". OppoPodsManager issue #1 asking for Buds 3 support was never followed up. S11 claims success but publishes no evidence. | Unconfirmed | S4 README L110-116; S5 issue #1; S11 |
| Bearer exposed to macOS | **Both.** SDP `0000079A` "enco link" on **RFCOMM channel 15**, and BLE GATT `0000079A` with `0100079A` (writeWithoutResponse, write) and `0200079A` (read, notify). Which one answers OPO frames is untested. | **Observed** (read-only, 2026-10-12) | PhaseB-Report §4.2–4.3 |
| BLE manufacturer data | Company `0x079A` (OPPO per the SIG list), then `14 3C 06` = product ID `063C14` LE, then the classic address byte-reversed | Observed bytes; the product-ID reading is a strong Hypothesis | PhaseB-Report §4.3 |
| Device ID record | VendorID `0x02B0` (Bestechnic), ProductID `0x0000`, Version `0x001F` | Observed | PhaseB-Report §4.2 |

### OnePlus Nord Buds 3 Pro (protocol reference)

| Field | Value | Label | Source |
|---|---|---|---|
| Product ID | `064414` | Documented | S5 |
| Works over BLE GATT from macOS | Yes | Documented | S1, S2 |
| Needs the `0x0500` time reply | Yes | Documented | S4 issue #2 |
| Event ids offered | `02`, `01` only | Documented | S4 issue #2 |
| ANC byte meaning | Conflicting: S2/S3 say `01` = ANC; S1 says `01` = Off; S4's set table says `01` = Off and `02` = ANC | Unresolved. Expect S4's mapping. | S1 `ANCWireMapping.swift`; S2 README L140; S4 |

### Known traps

- **Nord Buds 3** (`065014`) uses older ANC bit values. Buds 4's "Off" bytes switch ANC **on** there (S4 L258-260). This is why a command is never assumed to carry over between models.
- **S6's product-ID map** lists "OnePlus Buds 3" as `045010`. That id is absent from the HeyMelody list, so the entry is treated as unreliable.

---

### realme (TL family; research 2026-10-12)

Sources: S4 `models.json` and PROTOCOL.md L264-271, L379-426, L516, L628-681; S5 `DeviceModels.json`; S10 `docs/reference/realme-models.json`; S12 `DeviceProfile.swift` L103-153; S15 realme coordinators, `AncConfigValue`, `OppoHeadphonesSupport` L216-221, L474-489.

| Fact | Value | Label |
|---|---|---|
| Model ids | Buds Air 5 `062012`, T300 `062412`, Air 5 Pro `061C12`, Air6 `063412`, Air6 Pro `063012`, Air7 Pro `064C12`, T310 `063C12` | Documented (S5) |
| Transport | `0000079A-…` with `supportSpp` true. Some realme models (S15: Air6 Pro, T200) use the **standard SPP** `00001101-…` | Documented |
| Noise control | **The set value equals the read value**: Off `01`, Transparency `02`, Light `04`, Deep/plain ANC `08`, Medium `10`, Smart `20`. May be reported as 1 byte. The OnePlus split set/read table does *not* apply. | Documented; verified by S12 on T500 Pro and by S15 on Air6 Pro/T200. Not on the owner's models. |
| S10 realme noise mapping (NC `01`, Off `02`, …) | Contradicts all hardware evidence; not used | Hypothesis: S10 is wrong |
| Control byte | Send `00`; accept `04`/`08` on receive | Documented (S15) |
| Handshake | S15 never sends `0x0100`; OneBuds treats a missing handshake reply as non-fatal | Documented |
| Voice-assistant gesture | `04` on realme (`03` on OnePlus) | Documented (S15, S10); S4 conflicts |
| EQ presets | 0 Pure Raw, 1 Deep Bass, 2 Pure Vocals, 3 Pure Bass | Documented (S4) |
| Feature ids | Wear `04`, game `06`, dual `11`. **Power saving is `05`: never written.** | Documented (S4) |
| realme Buds Wireless 2 | `protocolType 2`, SPP `1101`, id `C1E2B1`: older realme Link protocol, **not OPO**, undocumented | Documented (S5, S10) |

## 8. macOS Bluetooth lessons (Documented)

### IOBluetooth RFCOMM recipe

Sources: S12, S13, S14.

1. Find the device with `IOBluetoothDevice.pairedDevices()`, matching by name or by `getServiceRecord(for:)` with the 079A UUID.
2. **Off the main thread:** if the device is not connected, call `openConnection()`. It blocks for 3–15 s.
3. Call `performSDPQuery(nil)`.
   - **Never** use the `uuids:` variant. Since Ventura it returns success but never calls back.
   - Then poll `getServiceRecord(for:)` for up to about 8 s. After a phone multipoint session, the buds take 3–5 s to expose SPP.
4. Read the channel with `getRFCOMMChannelID`.
5. **On the main run loop,** call `openRFCOMMChannelAsync`.
   - Keep a strong reference to the delegate.
   - The status codes and the completion delegate are unreliable. Treat the channel as open on completion **or** when `isOpen()` becomes true. Time out after about 10 s; a stale SDP record can mean the open never completes.
6. **Reads:** copy the bytes inside `rfcommChannelData` before hopping threads. Frames can be split or merged, so resync on `AA`.
7. **Writes:** chunk to `getMTU()`.
8. **Late callbacks:** tag each connection with a generation number and ignore callbacks from an older one.
9. **Teardown:** clear the delegate, `closeChannel()`, and release the channel on quit. macOS grants only one channel per device, so a leaked channel blocks the next launch. Never let two processes compete for it.
10. **Connection notifications:**
    - `register(forConnectNotifications:)` misses devices that were already connected at launch.
    - The disconnect notification is one-shot: re-arm it on every connection and always `unregister()`.
11. **Sleep and wake:** on `NSWorkspace.didWakeNotification`, wait about 1 s, re-read the connection state, and cancel any user action that was pending.
12. **Signing and permissions:**
    - Sign the app, even ad-hoc. Without a signature, TCC cannot read `NSBluetoothAlwaysUsageDescription` and the app crashes on first Bluetooth use.
    - Changing the bundle id or the signing identity re-prompts for Bluetooth. Keep both stable.
    - A `CBCentralManager` can be used to detect `.unauthorized`.
    - None of the reference apps is sandboxed.

### Core Bluetooth (S1, S2, S11)

- Discovery: `retrieveConnectedPeripherals(withServices:)` with 079A, then a scan **without** a service filter, because many buds do not advertise 079A.
- Session readiness:
  - Wait until notify is enabled on `0200079A` before sending anything.
  - Skip service `0000079C` and any characteristic that requires encryption. They can force a disconnect.
- `connect` has no timeout of its own. Add one.

### Capture procedure (S15), for Phase B if needed

1. On Android, enable Developer options, then turn on "Enable Bluetooth HCI snoop log".
2. Toggle Bluetooth off and on.
3. Use HeyMelody: connect, then change one setting at a time.
4. Run `adb bugreport dump.zip` and take the log from `FS/data/misc/bluetooth/logs/`.
5. Open it in Wireshark. Use the `btspp`/`btrfcomm` filters for classic links or `btatt` for BLE, then search for `aa` frames.

---

## 9. Open conflicts (resolve on hardware)

| # | Question | Candidates |
|---|---|---|
| C1 | Which bearer works for Buds 3 on macOS | **Both are exposed (Observed):** RFCOMM channel 15 and GATT 0100/0200079A. Which one responds still needs an active probe. |
| C2 | Buds 3 ANC level bits | **Resolved (Verified 2026-10-12, fw 127.127.101):** the S4/S12 table is correct. The set masks Off `01`, ANC `02`, Transparency `04`, Deep `10`, Medium `20`, Light `40`, Smart `80` each read back as `0x0008`/`0x0080` (generic ANC lands on Smart)/`0x0100`/`0x0010`/`0x0020`/`0x0040`/`0x0080`. S11's mapping is wrong for Buds 3. |
| C3 | Subscribe payload | **Observed:** `0x0205 06 01 02 03 04 08 0B` (count first, S4/S10 form) was answered `0x8205`. The reply `01 06 01 00 02 00 …` starts with `01`; meaning unknown. |
| C4 | Is the `0x0500` time request sent by Buds 3, and is it required? | **Observed:** not sent in two sessions (about 6 s and about 2 s); the link stayed up without a time reply. The app still answers if asked. |
| C5 | Wear-detection feature id | **Observed:** `0x010D` returned `04=1` (with `06=1`, `11=1`). Id `04` exists; its meaning has not yet been confirmed by toggling it. |
| C6 | Which push events Buds 3 offers | **Observed:** `0x8200` → `00 09 01 02 03 04 08 0B F1 F2 F3`. Unsolicited on connect: `0x0204 06` (multi-device list, contains personal data and is always redacted) and `0x0204 02` (wear status). |
| C7 | FE2C traffic | Observed characteristic set `FE2C1233`–`FE2C1238` matches Google Fast Pair. Hypothesis strengthened; not part of OPO. |

---

## 10. Implementation provenance log

| Date | OneBuds file | Facts used (§) | Notes |
|---|---|---|---|
| 2026-10-12 | `Sources/OneBudsDiagnostics/KnownUUIDs.swift` | §3 (UUIDs only, used as labels and lookup filters) | Phase B probe. Written independently; no protocol frames. |
| 2026-10-12 | `Sources/OneBudsProtocol/*` (frame codec, commands, parsers, time reply, redaction rule) | §4–§6 | Clean-room from the tables. Fixtures are the bytes printed by S1, S4 and S12, plus captured Buds 3 replies. |
| 2026-10-12 | `Sources/OneBudsCore/*` (OPOv1Session, registry, DeviceManager, MockTransport, simulator) | §5–§7 | Clean-room; per-model values live in `DeviceRegistry.swift` with source keys. |
| 2026-10-12 | `Sources/OneBudsBluetooth/RFCOMMTransport.swift`, `BLETransport.swift`, `BluetoothConnector.swift` | §3, §8 | Written independently from the documented IOBluetooth and Core Bluetooth lessons (S12, S13, S14 ideas, no code). |
| 2026-10-12 | `Sources/OneBudsApp/*` | — | Original SwiftUI. |
| 2026-10-12 | `Sources/OneBudsProbe/*` | §8 (IOBluetooth SDP lessons: unfiltered `performSDPQuery`, RFCOMM channel from SDP) | Written independently from the documented lessons. No code copied from S12, S13 or S14. |
