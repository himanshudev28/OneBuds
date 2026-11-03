# Changelog

## v0.2.0

**77 earbud models, Bluetooth LE with automatic fallback, and a redesigned menu bar.**

### Earbuds
- **73 more OnePlus, OPPO and realme models** can be controlled, including Buds 4, Buds Pro 2 / Pro 3, Nord Buds 3 / 4, the OPPO Enco Air, Free and X series, Enco Buds2, and realme Buds Air 5 Pro to Air8 Pro, the T-series and Wireless 3 / 5. They are built from published protocol data and marked **Experimental** until tested on hardware. The full list, with each model's features, is in [Documentation/ModelCatalog/Models.md](Documentation/ModelCatalog/Models.md).
- **Each model shows only its own features.** A control appears only when its values are published for that model, and the earbuds' own capability list can still hide it.
- **The product id the earbuds report decides the model**, so special editions that share a name with the base model get the right controls. A product id shared by two models never selects one on its own.
- Older models on the legacy 1107 service are recognised for diagnostics only; realme's older non-OPO protocol and DIZO models are listed as unsupported.

### Connection
- **Bluetooth LE (GATT) first, Classic Bluetooth (RFCOMM) as fallback.** OnePlus Buds 3 passed the full 17/17 feature test on both routes.
- **Switches back to GATT** when it becomes available again, without a visible disconnect.
- New **Settings ▸ General ▸ Connection**: Automatic, GATT only, or RFCOMM only.
- The main window shows why OneBuds fell back, and Diagnostics lists every route it tried.
- More robust GATT: tries each matching Bluetooth LE device, checks the characteristics, sizes writes to the link and reports pairing errors clearly.

### New controls (Experimental)
- Custom EQ presets with an editor, BassWave strength, 3D audio, smart volume, the touch-and-hold noise cycle and call controls.
- Find my earbuds, ear-tip fit test and Golden Sound hearing test.
- Output volume in the menu bar and low-battery notifications.

### Design
- New menu-bar panel on macOS 15 and later, with an animated open that closes on an outside click, Escape, or switching apps.
- System Settings-style main window with coloured sidebar icons and a centred overview.

### Install
Download `OneBuds-0.2.0.dmg`, open it and drag OneBuds to Applications. It needs macOS 14 or later.
- The download is not notarized. The first time, right-click OneBuds and choose **Open**, or allow it in System Settings ▸ Privacy & Security.
- macOS asks for Bluetooth permission on first launch.

## v0.1.0

First release: a native macOS menu-bar app for OnePlus Buds 3 (hardware-verified) with Experimental support for Nord Buds 3 Pro and realme Buds Air 5 / T300. Battery, noise control, EQ presets, game mode, gestures, connection card and Demo mode.
