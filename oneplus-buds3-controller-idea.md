# OnePlus Buds 3 Controller — Idea and References

## The idea

An open, privacy-first controller for **OnePlus Buds 3** that works without the HeyMelody app or a phone.

It starts as a **browser app (PWA)** on the Mac and later becomes a **native Mac menu-bar app** built with Tauri and Rust, similar to what GalaxyBudsClient and galaxy-buds-mac do for Samsung earbuds.

### What it should do

- Show battery for the left bud, right bud, and case, including charging status
- Switch noise control: off, noise cancelling, transparency (and adaptive, if the buds support it)
- Change the equalizer: presets and a custom curve
- Remap touch controls for each earbud
- Toggle game mode (low latency), in-ear detection, and other settings HeyMelody offers
- Show device details such as model and firmware version (read only)

### Principles

- Everything stays on your own devices: no accounts, no cloud, no tracking
- Only open-source building blocks with permissive licenses
- No firmware updates, so there's no risk of damaging the earbuds
- The app never pretends a setting changed; it only shows a change once the earbuds confirm it

### How to get there

1. **Find out how the Buds 3 talk to HeyMelody.** It's either Bluetooth Low Energy (the "OPO" service other OnePlus buds use) or the classic Bluetooth serial channel. Capture your phone's Bluetooth traffic while using HeyMelody to confirm.
2. **Decode each setting** from those captures and check it works by sending it from the Mac.
3. **Build the browser app** on what you've verified.
4. **Build the native Mac menu-bar app** so it works without a browser.

---

## Helpful links

### OnePlus / OPPO protocol work

| Link | What it is | License |
|---|---|---|
| https://github.com/AasheeshLikePanner/cracked-oneplus-buds | Nord Buds 3 Pro noise-control from a Mac over Bluetooth LE, with the handshake and example messages | MIT (safe to reuse with credit) |
| https://aasheesh.vercel.app/blog/oneplus-buds | Full write-up of how that protocol was reverse-engineered | Blog |
| https://github.com/kunalagra/OtoControl | Browser-based headphone controller that includes OPPO/OnePlus | AGPL (read, don't copy code) |
| https://github.com/Zhaoyi-ya/OppoPodsManager | Windows/Linux controller for OPPO, OnePlus, and realme, 137 models | Check before reuse |
| https://github.com/1812z/oppopods | OPPO earbud control for Android/HyperOS | GPL-3.0 (read, don't copy code) |
| https://github.com/digisatapathy2025/oneplus-buds-mac | Native Mac menu-bar app for OnePlus, OPPO, and realme | No open license (read only) |
| https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller | Mac menu-bar controller for OPPO Enco earbuds | Check before reuse |
| https://noctalia.dev/plugins/community/oppo-pods | Linux plugin using the Bluetooth serial route, 200+ models | Check before reuse |

### Reference apps (Samsung, for structure and ideas)

| Link | What it is | License |
|---|---|---|
| https://github.com/timschneeb/GalaxyBudsClient | The cross-platform earbud manager to model the app on | GPL-3.0 (read, don't copy code) |
| https://github.com/vedatkilic/galaxy-buds-mac | Native Mac menu-bar app; its release notes are full of practical Mac Bluetooth lessons | Check before reuse |

### Guides

| Link | What it covers |
|---|---|
| https://codeberg.org/Freeyourgadget/Gadgetbridge/wiki/BT-Protocol-Reverse-Engineering | How to capture and analyse Bluetooth traffic from an Android phone |
| https://developer.chrome.com/blog/serial-over-bluetooth | How a browser can talk to earbuds over the Bluetooth serial channel |
