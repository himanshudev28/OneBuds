# Hardware test checklist

Use this to test OneBuds with real earbuds connected to the Mac. For each step, record the date, the earbud firmware (shown in **Device Info**) and the result. Then send the results back so the matching feature in `DeviceRegistry.swift` and `Features.md` can be marked **Verified**.

Before you start:

- Install the app with `scripts/build-app.sh --install`.
- In **Diagnostics**, turn on **Record raw packets**. Export a report after any failure.
- Keep the phone's HeyMelody app closed unless a step asks for it.

## Connection

- [ ] Buds in your ears and connected to the Mac for audio. Open OneBuds: the menu-bar icon turns into earbuds and the popover says **Connected**. Device Info shows `063C14` and `127.127.101`.
- [ ] Put both buds in the case and close the lid. Within a few seconds the status leaves Connected and the battery and settings disappear: no stale values.
- [ ] Open the case and take the buds out. OneBuds reconnects without any clicks, within about 30 s.
- [ ] Click **Disconnect** in Overview. It stays disconnected. Click **Connect** and it reconnects.
- [ ] Turn Bluetooth off in Control Center. The popover says **Bluetooth is off**. Turn it on and OneBuds reconnects.
- [ ] Sleep the Mac for at least 1 minute, then wake it. OneBuds shows correct values again, and nothing stays stuck on "Waiting for the earbuds to confirm…".
- [ ] Quit OneBuds, then open it again. It connects. Audio keeps playing throughout.

## Battery

- [ ] The left, right and case percentages match HeyMelody on the phone (open the phone app only for this check).
- [ ] Put one bud in the case. That bud's value updates, or disappears. The charging bolt appears where appropriate.
- [ ] Settings → **Show battery percentage**: the menu bar shows the lower bud value. Turn it off and the percentage disappears.

## Noise control (at least one bud in an ear)

- [ ] Popover: choose **Off**, then **Transparency**, then **ANC**. Each time you hear the change, and the control settles on the new value with "Confirmed by the earbuds".
- [ ] With **ANC** selected, try each **Level**: Smart, Deep, Medium, Light. Each one is confirmed. (Sources disagree on these bytes; report anything that sounds wrong or is reported back differently.)
- [ ] Long-press a bud to cycle noise control. OneBuds follows without a click (push event).
- [ ] Take both buds out of your ears and choose a mode. OneBuds shows "refused: put at least one earbud in your ear", and the selection goes back to the previous mode.

## Equalizer, features, gestures

- [ ] Equalizer: pick each preset. It is confirmed, and you hear the difference.
- [ ] Game mode, in-ear detection and dual connection: switch each one and switch it back. Each change is confirmed. Check that the behaviour actually changes (for example, in-ear detection pauses music when you take a bud out).
- [ ] Touch Gestures: change Left → Double tap to **Play / pause**. It is confirmed, and double tap now plays and pauses. Restore it to **Next track**.

## Phone competition (hypothesis from mac.md §7)

- [ ] Phone Bluetooth **on**, HeyMelody **open**: does OneBuds still connect and control? Change a mode in HeyMelody: does OneBuds follow?
- [ ] Phone Bluetooth **off**: repeat the noise-control step.

## Demo mode

- [ ] Settings → Demo mode on: DEMO appears in the menu bar, the popover and the window. No Bluetooth traffic shows in the packet log. Turn it off and the real buds reconnect.

## realme (Buds Air 5, Buds T300)

- [ ] Connect the realme buds to the Mac. OneBuds connects and Device Info shows `062012` (Air 5) or `062412` (T300).
- [ ] Battery matches the realme Link app.
- [ ] Noise control: Off, Transparency, ANC, and on the Air 5 the levels Light/Deep/Medium/Smart. Each is confirmed and audible.
- [ ] EQ presets (Pure Raw, Deep Bass, Pure Vocals, Pure Bass), game mode, gestures.
- [ ] realme Buds Wireless 2: OneBuds shows "not a supported model" and sends nothing.

## Results log

| Date | Firmware | Step | Result | Notes |
|---|---|---|---|---|
| 2026-10-12 | 127.127.101 | Connect + read all (app self-test) | Observed: all reads OK over RFCOMM ch 15 | First run: buds in the open case (100/100/100, Off). Second run: buds worn (L/R 100, ANC Smart). Done by Claude with owner approval; values not yet confirmed by the owner. |
| 2026-10-12 | 127.127.101 | Feature test (owner-requested) | **17/17 PASS**, all restored | Noise: all 7 modes. EQ: presets 1/2/3 and back to 0. Game mode and in-ear switch: on/off. Left double-tap gesture: changed and restored. Pushes: 9 noise, 4 EQ. Dual connection skipped at the owner's request. |
| 2026-10-12 | 127.127.101 | Owner check of the redesigned UI (popover, Settings, menu shortcuts, gestures) | Owner reported "everything working" | Latest build installed to /Applications at 12:37. |
