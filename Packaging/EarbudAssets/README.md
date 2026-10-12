# Connection card artwork

Drop licensed artwork for a supported model here, named by its `DeviceRegistry` profile id. `scripts/build-app.sh` copies it into `OneBuds.app/Contents/Resources/EarbudAssets/`.

| File | Shown as |
| --- | --- |
| `<profile-id>.usdz` | A 3D model with a gentle sway (RealityKit, macOS 14 and later). It is centred, scaled to fill about 85 % of the frame, seen from slightly above and lit by a key and a rim light, all automatically. Keep it under about 5 MB, with real-world units and PBR materials. |
| `<profile-id>.png` or `.heic` | A static product render (transparent background, square, at least 288 × 288 px). |

For example, `oneplus-buds-3.usdz`.

Rules:

- **Use only artwork you are licensed to redistribute, of that exact model.** No look-alikes or other brands' earbuds.
- **Record the source and licence** in `THIRD_PARTY_NOTICES.md`.

The card uses the model, else the render, else the generic earbuds-and-case symbol. A file that fails to load falls through to the next.

Before shipping, build the app and check the model:

```sh
scripts/build-app.sh
ONEBUDS_ARTWORK_CHECK=/tmp/artwork build/OneBuds.app/Contents/MacOS/OneBuds
open /tmp/artwork   # PNGs at rest and mid-sway, light and dark, plus artwork-check.txt
```

Status, October 2026: no licensed OnePlus Buds 3 artwork has been found (see the README, "Connection card artwork").
