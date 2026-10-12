
# Build OneBuds — Native macOS OnePlus, OPPO & realme Earbud Manager

Act as a senior macOS engineer specializing in Swift, SwiftUI, Core Bluetooth, IOBluetooth, Bluetooth protocol analysis, and native application architecture.

Build **OneBuds**, an unofficial native macOS menu-bar application inspired by HeyMelody that controls compatible OnePlus, OPPO, and realme earbuds directly from a Mac, without a phone or the HeyMelody app.

**Target platform:** macOS 14 (Sonoma) or later, Apple Silicon. Development machine: MacBook Air M1.

**My hardware:** OnePlus Buds 3. This is the first device that must work on real hardware. OnePlus Nord Buds 3 Pro is the best-documented protocol reference, but I do not own one, so it cannot be my hardware test device.

**Primary goal:** implement real Bluetooth communication and verified earbud controls. A beautiful interface is important, but functional hardware integration takes priority over simulated features.

**Long-term goal:** an architecture that can support any OnePlus, OPPO, or realme model, whichever Bluetooth transport it uses, with each model enabled only after it is verified.

## 0. How to work with me

- Work phase by phase (see section 12). **At the end of each phase, stop, report what is complete versus unverified, and wait for my go-ahead.**
- Phases that need physical hardware (B, E, F, and H) require me to run tests. Give me exact steps, then **wait for my results**. Never assume a hardware test passed.
- When a decision depends on information you do not have (UUIDs, tokens, packet formats), ask me or give me a capture procedure. Do not guess.

## 1. Research existing projects before coding

Study these references.

### Primary (native macOS, protocol details)

| Repository | Notes | Licence |
|---|---|---|
| https://github.com/vedanth-jadhav/open-oneplus-buds | Swift menu-bar app. Uses BLE GATT through the OPO service (`0000079A…`). Hardware-tested on Nord Buds 3 Pro only. Auth token `B5 50 A0 69` is documented as Nord Buds 3 Pro specific. Responses arrive on both the OPO and `FE2C` services. | MIT, reusable with attribution |
| https://github.com/AasheeshLikePanner/cracked-oneplus-buds | Original OPOv1 research: handshake and example packets | MIT, reusable with attribution |
| https://aasheesh.vercel.app/blog/oneplus-buds | Reverse-engineering write-up | Blog, cite as a source |

### Broader protocol and model coverage (read for knowledge, check licence before reuse)

| Repository | Notes | Licence |
|---|---|---|
| https://github.com/spizganed/QuickBuds | Android/Windows/Linux, 127 models. Lists OnePlus Buds 3, but users have not confirmed it on hardware. Has protocol documentation. | GPL-3.0: **read only, do not copy code** |
| https://github.com/Zhaoyi-ya/OppoPodsManager | Windows/Linux, 137 OPPO/OnePlus/realme models. Likely uses the classic RFCOMM/SPP route. | Verify before reuse |
| https://noctalia.dev/plugins/community/oppo-pods | Linux plugin using the classic Bluetooth serial (RFCOMM) route, 200+ models | Verify before reuse |
| https://github.com/1812z/oppopods | OPPO earbud control for Android/HyperOS | GPL-3.0: **read only** |
| https://github.com/kunalagra/OtoControl | Browser-based controller that includes OPPO/OnePlus | AGPL: **read only** |
| https://github.com/digisatapathy2025/oneplus-buds-mac | Native Mac menu-bar app for OnePlus/OPPO/realme | No open licence: **read only** |
| https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller | Mac menu-bar controller for OPPO Enco | Verify before reuse |

### Architecture and UX inspiration only

| Repository | Notes | Licence |
|---|---|---|
| https://github.com/timschneeb/GalaxyBudsClient | Cross-platform earbud manager: structure and feature ideas | GPL-3.0: **read only** |
| https://github.com/vedatkilic/galaxy-buds-mac | Native Mac menu-bar app. Its release notes contain practical macOS Bluetooth lessons. | Verify before reuse |

### Guides

- Android Bluetooth capture and analysis: https://codeberg.org/Freeyourgadget/Gadgetbridge/wiki/BT-Protocol-Reverse-Engineering

Inspect README files, source code, protocol documentation, issues, tests, and licences.

Before reusing code:

- Confirm the licence of every repository and relevant dependency yourself. The table above is a starting point, not a substitute.
- Check attribution, redistribution, and derivative-work obligations.
- Do not copy GPL-, AGPL-, unlicensed, or otherwise restricted code into this project. Protocol *facts* learned from them (UUIDs, command IDs, byte layouts) may be used if they are recorded with their source and re-implemented independently.
- Record all protocol sources and implementation provenance in `Documentation/ProtocolSources.md`.
- Label every protocol fact as **Documented** (from a source), **Verified** (tested on my hardware), or **Hypothesis**.

Prefer adapting a compatible (MIT/BSD/Apache) implementation, such as Open OnePlus Buds, over duplicating existing research.

## 2. Technology stack

Use:

- Swift 6 with strict concurrency checking.
- SwiftUI for the interface, `MenuBarExtra` for the menu-bar popover, and the Observation framework (`@Observable`) for state.
- **Core Bluetooth** for BLE GATT communication.
- **IOBluetooth** for classic Bluetooth RFCOMM/SPP communication and for listing paired devices.
- Foundation and Swift Concurrency for application logic.
- XCTest for unit and integration tests.
- **XcodeGen** (`project.yml`) to generate the Xcode project. Never hand-edit `.pbxproj` files. Commit `project.yml` and regenerate the project from it.
- `ServiceManagement` (`SMAppService`) for the optional launch-at-login setting.

Do not use Electron, Tauri, React, a browser-based UI, a web server, or a cloud backend. Do not add third-party dependencies without asking me first.

Keep the application entirely local. Do not add accounts, analytics, crash reporting, or remote services.

## 3. Application design

OneBuds is a **menu-bar-first** app. People check battery and switch noise control many times a day, so those actions must be one click away.

### Menu-bar popover (primary interface)

- Menu-bar icon that reflects connection state, with an optional battery percentage next to it.
- Popover showing:
  - Connected device name and connection state.
  - Left, right, and case battery shown separately, with charging indicators, only when the device reports them.
  - A noise-control segmented control (Off / ANC / Transparency / Adaptive) that shows only the modes the device supports.
  - Quick toggles for verified features (for example game mode).
  - Buttons to open the main window and to quit.

### Main window (secondary, for detailed settings)

Native layout with a sidebar and a content area, containing:

1. Overview (device, battery, connection).
2. Noise control.
3. Equalizer (presets and custom curve, if supported).
4. Touch gestures (per earbud, if supported).
5. Device information (model, firmware, read only).
6. Bluetooth diagnostics (services, characteristics, raw packet log, transport in use).
7. Compatibility (the model registry, status, and evidence).
8. Settings (launch at login, menu-bar display options, demo mode toggle).

### Design requirements

- Light and dark appearance that follows the system.
- Consistent typography, spacing, and visual hierarchy. Prefer system fonts and SF Symbols.
- Subtle animations and native controls.
- Clear states for connecting, loading, applied (confirmed by the device), pending, unsupported, experimental, and error.
- Accessible controls with VoiceOver labels and full keyboard navigation.
- No unnecessary decorative elements.
- A control for an unsupported feature is hidden. A control for an experimental feature is shown with a visible "Experimental" badge.

## 4. Bluetooth architecture

### Transport abstraction

Earbud families use different transports. Define:

```swift
protocol EarbudTransport: Sendable {
    var kind: TransportKind { get }          // .ble, .rfcomm, .mock
    func connect() async throws
    func disconnect() async
    func send(_ frame: Data) async throws
    var incoming: AsyncStream<Data> { get }
    var state: AsyncStream<TransportState> { get }
}
```

Implement:

- `BLETransport`: Core Bluetooth (`CBCentralManager`, `CBPeripheral`).
- `RFCOMMTransport`: IOBluetooth (`IOBluetoothDevice`, `IOBluetoothRFCOMMChannel`), opening the channel by SDP service UUID.
- `MockTransport`: deterministic, scriptable, for tests and the labelled demo mode.

The protocol layer must depend only on `EarbudTransport`, never on Core Bluetooth or IOBluetooth directly.

### Device discovery

Earbuds already connected for audio often stop advertising over BLE, so a plain scan may never find them. Discover in this order:

1. **Already-connected BLE peripherals:** `CBCentralManager.retrieveConnectedPeripherals(withServices:)` using the known service UUIDs from the registry.
2. **Paired classic devices:** `IOBluetoothDevice.pairedDevices()`, matched by name or address and then by SDP service records.
3. **BLE scan:** `scanForPeripherals` as a fallback, with a timeout.

Show which discovery path found the device in the diagnostics screen.

### Core Bluetooth layer

Implement:

- Central manager initialization and adapter state monitoring (powered off, unauthorized, unsupported).
- Connection, disconnection, and reconnection handling (for example when the buds go back in the case and come out again).
- GATT service and characteristic discovery.
- Reads and writes with the write type each characteristic supports (with or without response).
- Notification subscriptions on **every** service where responses may arrive (Open OnePlus Buds documents responses on both OPO and `FE2C`).
- Timeouts and error handling.

### Concurrency

- Core Bluetooth and IOBluetooth objects are not `Sendable`. Confine each transport's framework objects to a single dedicated serial `DispatchQueue` (passed to `CBCentralManager`) or to a single actor, and bridge delegate callbacks into `AsyncStream`s.
- UI-facing state lives in `@MainActor` `@Observable` models.
- No Bluetooth or protocol logic inside SwiftUI view files.
- The project must compile cleanly under Swift 6 strict concurrency with no warnings suppressed.

### Permissions and configuration

- `Info.plist`: `NSBluetoothAlwaysUsageDescription` with a clear explanation.
- If App Sandbox is enabled, add the `com.apple.security.device.bluetooth` entitlement.
- Set `LSUIElement = YES` so the app lives in the menu bar without a Dock icon (the main window can still be opened).
- Handle the case where Bluetooth permission is denied: explain the problem in the UI and link to System Settings → Privacy & Security → Bluetooth.
- Document all of this in the README.

Do not assume every earbud exposes the same services, transport, or advertising behavior.

## 5. Protocol implementation

Define a protocol abstraction:

```swift
protocol EarbudProtocol {
    init(transport: EarbudTransport, profile: DeviceProfile)
    func startSession() async throws          // handshake / registration / auth
    func capabilities() -> Set<Capability>     // only verified or experimental ops
    func perform(_ command: EarbudCommand) async throws -> EarbudResponse
    var events: AsyncStream<EarbudEvent> { get } // unsolicited notifications
}
```

Start with **OPOv1**, using Open OnePlus Buds and the cracked-oneplus-buds research. Add other implementations (for example an RFCOMM-based OPPO protocol) only when research or captures justify them.

The protocol layer must support:

- Packet encoding and decoding.
- Frame length and checksum validation (if the format has a checksum).
- Session initialization, registration, and authentication when required.
- **Per-model auth tokens and parameters stored in the device profile, never hard-coded in protocol logic.**
- Command sequencing, with one outstanding request per command type unless the protocol allows more.
- Response correlation and parsing.
- Unsolicited notification handling (battery changes, mode changes made from the earbuds or the phone).
- Command timeouts with a typed error.
- Device-specific response mapping.
- Error reporting and diagnostic logging.

Rules:

- Do not invent UUIDs, packet formats, command identifiers, authentication tokens, or setting values.
- Do not brute-force or guess authentication tokens.
- Do not assume a command that works on one model works on another.
- Do not treat a successful Bluetooth write as proof that the device applied the setting. The UI shows a change as applied **only after the device confirms it** (an acknowledgement or a read-back).
- Where possible, read the setting back from the device to verify it.
- No firmware updates, factory resets, or undocumented destructive commands.

## 6. Device compatibility registry

Create a typed, data-driven registry so that adding a model is a matter of adding a profile.

Each `DeviceProfile` contains:

- Manufacturer and model identifier.
- Display name and name-matching rules (Bluetooth name patterns).
- Transport kind and transport parameters (BLE service/characteristic UUIDs, or RFCOMM service UUID).
- Protocol implementation and protocol parameters (auth token and similar).
- Compatibility status.
- Per-capability status (each feature can be Verified, Experimental, or Unsupported independently).
- Tested firmware versions, when known.
- Known limitations.
- Source references (links to `ProtocolSources.md` entries).
- Hardware test evidence (date, firmware, what was tested, by whom).

Statuses: **Verified**, **Experimental**, **Unsupported**, **Unknown**.

Initial entries:

- **OnePlus Nord Buds 3 Pro:** protocol reference. Experimental in this app until someone tests it with OneBuds (documented as working in Open OnePlus Buds).
- **OnePlus Buds 3:** Unknown until Phase B determines its transport and protocol, then Experimental, then Verified per feature after my hardware tests.
- **Other OnePlus, OPPO, and realme models** listed as "likely compatible" by references: Unknown.

Rules:

- The UI shows only verified capabilities as fully supported. Experimental ones carry a visible badge.
- Never claim compatibility because two devices share a product family or a protocol name.

### Unknown-model diagnostics ("Help add my model")

So that more models can be added over time, provide a **read-only** diagnostics flow for unrecognised earbuds:

- List the transport, the discovery path, BLE services and characteristics with their properties, and RFCOMM/SDP service records.
- Never send writes to an unknown device unless the user explicitly runs a documented, non-destructive probe.
- Export a report to a local file with device addresses and serial numbers redacted by default. Nothing is uploaded.

## 7. Device manager and application state

Create a `@MainActor @Observable` central device manager responsible for:

- Active device and transport.
- Connection state.
- Current device profile.
- Discovered services, characteristics, and RFCOMM channels.
- Active protocol session.
- Battery information (left, right, case, charging), each value optional.
- Current noise-control mode.
- EQ state.
- Gesture configuration.
- Supported capabilities.
- Per-operation status: idle, pending, confirmed, failed, or timed out.
- Errors.

Requirements:

- Strongly typed Swift models and enums, no loosely typed dictionaries.
- State updates are safe, predictable, and match the real device.
- Handle external changes: the earbuds, a button press, or the phone's HeyMelody app may change settings. Update from device notifications instead of assuming the Mac is the only controller.
- **Hypothesis to verify in Phase E:** the phone's HeyMelody app may hold or compete for the control channel. Test with the phone's Bluetooth both on and off, document what happens, and show a helpful message if the channel is busy.
- Reset all device state on disconnect, failure, or device switch. No stale battery or mode values.

## 8. Real hardware behavior

Implement features incrementally, each verified on my OnePlus Buds 3 before moving on:

1. A reliable connection and diagnostics workflow.
2. One real, harmless command verified against the hardware (for example a device-info or battery query).
3. Device identification.
4. Battery queries and notifications.
5. ANC mode queries and switching.
6. EQ queries and configuration.
7. Touch gesture configuration.
8. Other verified capabilities (game mode, wear detection, dual connection, find my earbuds) only where supported.

For every feature, document in `Documentation/Features.md`:

- Required protocol command (bytes).
- Expected response.
- Verification method.
- Models and firmware tested.
- Known limitations.

Never show fabricated battery percentages or settings in the real-device interface.

A mock/demo mode is allowed during development, but it must be explicitly labelled in the UI ("Demo"), use only `MockTransport`, and be impossible to confuse with a real device.

## 9. Testing requirements

Write XCTest coverage for:

- Packet encoding and decoding, using captured real packets as fixtures where available.
- Malformed packets, invalid frame lengths, and bad checksums.
- Session state transitions, including auth failure.
- Command construction.
- Response parsing and correlation.
- Unsolicited notification handling.
- Device profile selection and name matching.
- Capability-based UI behavior (unsupported features hidden, experimental ones badged).
- Timeout handling.
- Unexpected disconnections mid-command.
- Error propagation.
- State reset after disconnecting or switching devices.
- Transport selection (BLE vs RFCOMM) from the profile.

Use `MockTransport` for deterministic unit tests.

Provide `Documentation/HardwareTestChecklist.md`: a manual checklist for real earbuds connected to macOS. It covers connect, reconnect after the case is closed, each feature, changes made from the phone, Bluetooth turned off and on, and sleep/wake.

Do not claim a feature is hardware-tested unless I have reported testing it on a physical device.

## 10. Security and reliability

- Keep Bluetooth communication local.
- Never upload device identifiers, packet captures, or diagnostics.
- Redact Bluetooth addresses and serial numbers in logs and exports by default.
- Use `os.Logger` with privacy annotations. Raw packet logging is opt-in, enabled only from the diagnostics screen.
- Validate incoming packet lengths and response formats before parsing.
- Handle unexpected device responses without crashing.
- Never automatically issue destructive or undocumented commands.
- No firmware modification.

## 11. Distribution

- Phase I starts with local development signing for my own Mac.
- Document the later option of Developer ID signing and notarization for sharing the app with others.
- No Mac App Store requirements for now.

## 12. Development phases

Stop after each phase, report, and wait for my go-ahead.

**Phase A: Research.** Audit the references, confirm licences, and summarize the known transports, UUIDs, tokens, and commands per model. Write `Documentation/ProtocolSources.md`. Present your findings, licence constraints, proposed architecture, and compatibility assumptions.

**Phase B: Determine how my OnePlus Buds 3 communicate (hardware).**
1. Give me a small command-line diagnostic tool (Swift, built with SwiftPM) that lists already-connected BLE peripherals with their services and characteristics, and paired classic devices with their SDP/RFCOMM services.
2. I run it with my Buds 3 connected and send you the output.
3. If the OPO service is present, try the Open OnePlus Buds handshake with a read-only query.
4. If the handshake fails or the service is absent, guide me step by step through an Android HCI snoop capture of HeyMelody (per the Gadgetbridge guide), then analyse the capture I provide.

**Outcome:** a documented transport, service, and authentication for the Buds 3, labelled Verified or Hypothesis.

**Phase C: Bluetooth layer.** Build the transport abstraction, `BLETransport` and/or `RFCOMMTransport` (whichever Phase B requires first; the other may be a stub), discovery, connection management, and a minimal diagnostics UI.

**Phase D: Protocol.** Implement and unit-test the session and packet handling for the protocol Phase B identified, with `MockTransport` and real packet fixtures.

**Phase E: First real command (hardware).** Connect to my Buds 3 and verify one harmless command. Test the HeyMelody phone-competition hypothesis.

**Phase F: Battery and noise control (hardware) plus the menu-bar UI.** Build the menu-bar popover around the features verified so far.

**Phase G: EQ, gestures, and the main window.** Implement EQ, touch gestures, and other supported features, then build the main window screens for them. Do not build UI for a feature until its protocol exists.

**Phase H: More models (hardware).** Add the unknown-model diagnostics flow and expand the registry with individually tested models.

**Phase I: Release.** Packaging, signing, README, troubleshooting guide, and regression tests.

At the end of each phase: run `xcodegen generate`, build, run all tests, fix failures, and report **complete / experimental / unverified** status.

## 13. Deliverables

- `project.yml` (XcodeGen) and the generated Xcode project.
- A native SwiftUI menu-bar application with a main window.
- A modular transport layer (Core Bluetooth BLE, IOBluetooth RFCOMM, and mock).
- A protocol abstraction and an OPOv1 implementation (plus others where justified).
- A data-driven device compatibility registry.
- The Phase B command-line diagnostic tool.
- Unit tests.
- `README.md` with build and run instructions, permissions, and troubleshooting.
- `Documentation/ProtocolSources.md` (sources, licences, provenance).
- `Documentation/Features.md` (per-feature protocol and verification record).
- `Documentation/HardwareTestChecklist.md`.
- A clear report of implemented, experimental, and unsupported features per model.

Start with Phase A: audit the reference projects and present your findings, licence constraints, architecture, and compatibility assumptions. Then stop and wait for me.

**Prioritize genuine device control, correct protocol behavior, and verified compatibility over the number of settings displayed in the interface.**
