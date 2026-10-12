# Phase B report: how the OnePlus Buds 3 communicate

Status: **complete.** The read-only probe ran 3 times. The owner-approved query probe and the app self-test also ran (2026-10-12). Outcome: **RFCOMM channel 15 is the working control channel for OnePlus Buds 3. Verification: Observed.**

This phase is **strictly read-only**. Labels are the same as in [ProtocolSources.md](ProtocolSources.md):

- **Observed:** read from a probe run on your Mac.
- **Documented:** from a cited source.
- **Hypothesis:** our own inference.

Section 4 holds the observed results.

---

## 1. The tool: `onebuds-probe`

It is built with SwiftPM only (no Xcode) and packaged as `build/OneBuds Probe.app`.

| Item | Value |
|---|---|
| Bundle identifier | `com.local.onebuds.probe` (stable) |
| Signing | "OneBuds Local Signing", a self-signed certificate kept in `~/Library/Keychains/onebuds-signing.keychain-db` |
| Designated requirement | `identifier "com.local.onebuds.probe" and certificate leaf = H"a38536b6…"`. This stays the same on every rebuild, so macOS keeps the Bluetooth permission. |
| Permission | `NSBluetoothAlwaysUsageDescription` is set. The app is launched through LaunchServices (`open`), so macOS asks for permission for **OneBuds Probe**, not for your terminal. |
| Dock icon | None (`LSUIElement`). It exits when finished. |
| Sandbox | Off |

### What it does

1. **Bluetooth permission.** Creates a Core Bluetooth central and records the permission state and the adapter state. It waits up to 60 s for you to answer the prompt.
2. **Paired classic devices.** Uses IOBluetooth (`IOBluetoothDevice.pairedDevices()`).
   - Every paired device is listed. Name, address, and SDP records are recorded only for **candidate** names (`oneplus|oppo|realme|enco|buds`). Other devices appear as `<non-candidate device>`.
   - For a candidate that is **already connected**, it refreshes SDP with `performSDPQuery(nil)`.
   - It dumps every SDP service record and attribute.
   - It reads each record's RFCOMM channel in two ways: from the API, and parsed from the ProtocolDescriptorList, as a cross-check.
   - It explicitly looks up `0000079A-…`, `00001107-…` and generic SPP `0x1101`.
3. **BLE.** Uses Core Bluetooth.
   - Calls `retrieveConnectedPeripherals(withServices:)` with `079A`, `1107`, `079C` and `FE2C`.
   - Runs a 12 s scan with no service filter. Neighbouring devices are counted but never recorded.
   - On up to 4 candidates, it connects and discovers services, included services, characteristics and their properties, and descriptors.
4. **Reports.** Writes `Diagnostics/onebuds-probe-<time>.txt` and `.json`, and prints the text version.

### What it never does

- Sends any OPO/HeyMelody frame. That includes the handshake and the `0x0500` time reply.
- Writes any GATT characteristic or descriptor, or enables any notification (`setNotifyValue`).
- Reads any vendor characteristic. With `--read-standard` it reads **only** the standard Device Information (`0x180A`) and Battery (`0x180F`) characteristics.
- Discovers characteristics inside service `0x079C` (S1 reports it can force a disconnect).
- Opens an RFCOMM or L2CAP channel. It never calls `openConnection` and never pages a disconnected device.

A grep of `Sources/` finds no `writeValue`, `setNotifyValue`, `openRFCOMM*`, `writeSync`/`writeAsync` or `openConnection` calls.

### Bluetooth traffic it can cause

These are standard discovery operations, not protocol messages:

- One SDP query to a buds pair that is already connected.
- A BLE connection, plus GATT discovery requests to read the attribute table.
- Standard GATT reads, only with `--read-standard`.

If macOS shows a **pairing dialog** during BLE discovery, click **Cancel** and tell me. That would mean the buds want an encrypted BLE link, which is a useful finding in itself.

### Privacy

- **Redacted by default:**
  - Addresses keep only their manufacturer prefix (OUI) plus a pseudonym that is only consistent within one run.
  - Core Bluetooth identifiers become pseudonyms.
  - Serial numbers are removed.
  - Use `--no-redact` only if you want full values.
- **What stays visible:** device names and model-level data, such as SDP Device ID vendor and product IDs. These are needed.
- **Nothing is uploaded.** `Diagnostics/` is in `.gitignore`.

---

## 2. What you need to do

1. Take the Buds 3 out of the case, wear them, and make sure they are **connected to the Mac** (System Settings → Bluetooth shows "Connected"). Play a few seconds of audio to confirm.
2. Run this in Terminal from the project folder:
   ```
   cd "/Users/himanshu/Downloads/Visual Studio/Web Dev/VIbe_code/HeyMelodyMac"
   scripts/run-probe.sh
   ```
3. When macOS asks whether **"OneBuds Probe" would like to use Bluetooth**, click **Allow**.
   - If you miss the prompt or deny it, enable it under System Settings → Privacy & Security → Bluetooth, then run again.
4. Wait about 30–60 s. The report prints in Terminal.
5. **Run it again with standard reads.** This reads the model and firmware strings only:
   ```
   scripts/run-probe.sh --read-standard
   ```
6. **Optional, but useful for the "phone competes for the channel" question.** Run step 2 once with the phone's Bluetooth **on** and once with it **off**, and note which was which.
7. Send me the contents of the `.txt` report(s) from `Diagnostics/`. You can also paste the Terminal output. Tell me if any dialog appeared.

**If a run hangs for more than 2 minutes:** press Ctrl-C, run `pkill -f onebuds-probe`, and tell me.

**If you want to undo the signing setup later:** run `scripts/remove-signing.sh`. It removes only the OneBuds keychain.

---

## 3. Known API limitations (Documented, to be confirmed by the run)

| # | Limitation | Source |
|---|---|---|
| L1 | Core Bluetooth on macOS never exposes Bluetooth addresses, so BLE and classic entries can only be matched by name. | Apple API design |
| L2 | `performSDPQuery` with a UUID filter has been unreliable since macOS 13, so the probe uses the unfiltered call and also polls `getLastServicesUpdate`. | ProtocolSources §8 (S13, S14) |
| L3 | Buds that are connected for audio often stop advertising, so BLE may only be found through `retrieveConnectedPeripherals`, or not at all. | ProtocolSources §8 (S1, S11) |
| L4 | SDP records can be stale if the buds were last seen while the phone held the link. | ProtocolSources §8 (S14) |
| L5 | `IOBluetoothDevice.isConnected()` can under-report while audio is active. | ProtocolSources §8 (S12) |

---

## 4. Observed results

**Runs.** Three runs on 2026-10-12, 11:00–11:04 local time, on macOS 15.7.3 (24G419).
- Buds 3 worn and connected to the Mac for audio.
- Phone Bluetooth state: not recorded.
- Run 2 used `--read-standard`.
- Run 3 followed two probe fixes: SDP completion detection and address masking.
- The results matched across runs, except for values that rotate (pseudonyms, BLE identifiers, one manufacturer-data byte).
- Clean report: `Diagnostics/onebuds-probe-20261012-110335.txt`.

### 4.1 Permission and packaging (Observed)

| Item | Result |
|---|---|
| Bluetooth permission | `allowedAlways`. The central reached `poweredOn` within 2.1 s on run 1. |
| Re-prompt after a rebuild | **None.** Runs 2 and 3 used rebuilt bundles with the same designated requirement and were ready within 0.1 s. The stable signing identity works. |
| Launch via `open --stdout` | Fails with LaunchServices error **-10810** if the output file already exists. Fixed in `run-probe.sh`. |
| `IOBluetoothDevice.getLastServicesUpdate()` | Returned the run time for **every** paired device, connected or not. It is unusable as a freshness signal. |
| `performSDPQuery(nil)` on the connected Buds 3 | Completion callback arrived after about 0.1 s with success. |

### 4.2 Classic Bluetooth: OnePlus Buds 3 (connected entry, OUI `88:92:CC`)

Class of device `0x240404` (audio/video, wearable headset). There are 12 SDP records:

| # | Service name | Service class | Transport | Notes |
|---|---|---|---|---|
| 9 | `"enco link "` | **`0000079A-D102-11E1-9B23-00025B00A5A5`** | **RFCOMM channel 15** | Profile descriptor SPP 1.2. API and parsed channel agree. |
| 2 | `"commonSpp "` | `0x1101` Serial Port | RFCOMM channel 12 | Generic SPP. Purpose unknown. |
| 7 | `"RFCOMM COM "` | `DF21FE2C-2515-4FDB-8886-F12C4D67927C` | RFCOMM channel 17 | S5 lists this UUID as a *GATT* service for some OPPO models. Purpose unknown. |
| 4 | — | `0x111E` Handsfree | RFCOMM: **record says 3, `getRFCOMMChannelID` returns 1** | Same mismatch in all 3 runs |
| 6, 8 | — | `0x1203` Generic Audio, `0x1108` Headset | RFCOMM channel 1 | |
| 0, 3, 5 | `"Advanced Audio"`, `"AVRCP Remote Control Target"` | AVRCP (`0x110F`, `0x110C`, `0x110E`) | L2CAP PSM `0x17` (AVCTP) | ProviderName `"MtView"` |
| 1 | — | `0x110B` A2DP sink | L2CAP PSM `0x19` (AVDTP) | |
| 10 | — | `0x1801` Generic Attribute | L2CAP PSM `0x1F` (ATT over BR/EDR) | |
| 11 | — | `0x1200` Device ID | — | VendorIDSource 1 (Bluetooth SIG). **VendorID `0x02B0` = Bestechnic (Shanghai)** per the SIG company list. ProductID `0x0000`, Version `0x001F`. |

- The legacy service `00001107-…` is **absent**.
- There is a second paired entry named "OnePlus Buds 3" (OUI `40:72:18`). It was not connected and has no cached records. Hypothesis: an older pairing.

### 4.3 BLE: OnePlus Buds 3

| Item | Result |
|---|---|
| Discovery | Two peripherals named "OnePlus Buds 3" appear each run. Peripheral A is found by `retrieveConnectedPeripherals` (filter 079A/1107/079C/FE2C) **and** by the scan. Peripheral B is found by the scan only. |
| Peripheral A advertisement | Manufacturer data `9A 07 14 3C 06 7F 90 03 98 04 <6 bytes> 1F B5 B5 00 03 00`. The 6 bytes are **the classic address, byte-reversed**, now masked. One byte varied between runs (`90`/`80`) and another varied (`0F`/`1F`). No service UUIDs are advertised. |
| Peripheral B advertisement | Service data for `0xFE2C` only, tx power −11 dBm |
| GATT (identical on A and B) | Services `0000079C-…` (not explored, by design), `0xFE2C`, and `0000079A-…`. No Device Information (0x180A) or Battery (0x180F), so `--read-standard` read nothing. |
| `0000079A` characteristics | **`0100079A-…`: writeWithoutResponse + write.** **`0200079A-…`: read + notify**, with a CCCD. |
| `0xFE2C` characteristics | `FE2C1233` (read); `FE2C1234`–`FE2C1237` (write + notify); `FE2C1238` (read + write + notify; its descriptors include three entries reported as UUID `0x0000`) |
| Connection and discovery | Connected and completed. **No pairing dialog** appeared and no disconnect occurred. Audio was unaffected as far as the run could tell. |

### 4.4 Interpretation (Hypothesis unless stated)

- **C1, which bearer: both bearers expose the control service (Observed).** It is RFCOMM channel 15 over SDP *and* GATT `0100079A`/`0200079A` over BLE. Which one *responds* to OPO frames is still unknown and needs an active probe.
- **Manufacturer data identifies the model (strong Hypothesis):**
  - The company ID `0x079A` is OPPO (Observed via the SIG list).
  - The next bytes `14 3C 06` are the little-endian form of product ID **`063C14`**, which matches HeyMelody's OnePlus Buds 3 entry (S5).
  - So discovery can match a model from advertising data without connecting.
- **C7, FE2C (Hypothesis strengthened):** the `FE2C1233`–`FE2C1238` characteristic set matches Google Fast Pair's layout. It is not part of OPO, and OneBuds will not touch it.
- **Two BLE peripherals.** Possibly the left and right buds each expose GATT, or one is a separate Fast Pair advertising identity. Not resolved by read-only means.
- **Chipset hint.** The Device ID vendor is Bestechnic, while the AVRCP ProviderName is "MtView". These are inconclusive and irrelevant to control.
- **Implementation consequence (Observed).** `getRFCOMMChannelID` can disagree with the record's ProtocolDescriptorList, as it does for Handsfree. `RFCOMMTransport` must cross-check against the parsed value and log any mismatch.

### 4.5 Still open

- The phone-on versus phone-off comparison has not been run.
- Whether the Buds 3 send the `0x0500` time request.
- Which bearer answers.
- Whether HeyMelody on the phone holds the channel.

## 5. What happens after the results (for your approval)

These are hypotheses until the results are in.

- **079A appears over RFCOMM:**
  - First transport: `RFCOMMTransport`, following the S12 pattern.
  - First active probe, if you approve: open the channel and send only the handshake `0x0100`, then product ID `0x0103`. Also reply to the buds' `0x0500` time request if it arrives.
  - Expected product ID reply: `00 14 3C 06` (`063C14`).
- **079A appears only over BLE GATT:** same first probe, sent through `0100079A` with notifications enabled on `0200079A`.
- **079A does not appear on either:** move to the Android HCI capture procedure (ProtocolSources §8).

No active probe will run until you approve it.

## 6. Active probe and app self-test (owner-approved, 2026-10-12)

The owner approved query-only traffic plus the time reply ("all approve"). The owner then asked for the full app to be built, and the app's normal read-only startup was run on the same buds. Logs:

- `Diagnostics/onebuds-session-20261012-113019.txt` (probe)
- `Diagnostics/onebuds-selftest.txt` (app)

The multi-device payload in both logs is redacted.

| Step | Result (Observed) |
|---|---|
| First attempt (11:14) | Neither route found the buds; they were not connected. Nothing was sent. |
| RFCOMM open | The SDP query and channel 15 open succeeded in about 0.6 s, after which the transport state became `connected`. |
| Unsolicited on open | `0x0204` event `06` (multi-device list: other devices' Bluetooth addresses and user-chosen names). Personal data, so it is always redacted. |
| `0x0100` handshake | `0x8100` `00 FF 77 5A EE E7 0E 22 00` after about 46 ms |
| `0x0103` product id | `00 14 3C 06` = **063C14**, which matches HeyMelody's OnePlus Buds 3 entry and the BLE advertisement |
| `0x0105` firmware | `"1,1,01,1,2,127,2,1,01,2,2,127,3,2,101"` = 127.127.101 |
| `0x0106` battery | `00 03 01 64 02 64 03 64` = L/R/case 100% (buds in the open case) |
| `0x0500` time request | **Not sent by the buds** in either session |
| App startup (self-test) | Connected in 1.4 s over RFCOMM. Subscribed to events `01 02 03 04 08 0B`. Read noise = Off (`0x0008`), EQ = 0, features `04/06/11` = on, and 12 gestures. Wear push: all three components in the case with the lid open. |
| BLE route | Not exercised: RFCOMM answered first. GATT `0100`/`0200079A` remain an untested fallback. |

**Conclusion:**

- **Transport:** RFCOMM, SDP `0000079A-…` → channel 15.
- **Auth:** none required.
- **Time reply:** not requested by Buds 3.

Every query and read is Observed on owner hardware. Every *set* command remains Experimental until the owner runs `HardwareTestChecklist.md`.
