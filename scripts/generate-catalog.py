#!/usr/bin/env python3
"""Generates Sources/OneBudsCore/DeviceCatalog.swift from Documentation/ModelCatalog/*.json.

The JSON files hold per-model protocol facts gathered from the sources in
Documentation/ProtocolSources.md (values only, never code), each with its sources, conflicts and
a confidence level. This script turns them into DeviceProfile values without adding anything the
data does not state:

- A model gets a control session (status Experimental) only if it speaks OPOv1 on the 079A service
  (or realme's SPP fallback), has a product id, and has noise or EQ values. Each capability is
  offered only when its parameters are present.
- Models on the legacy 1107 service (different handshake, not implemented) and models with no
  protocol values are diagnostics only (status Unknown).
- realme's older non-OPO protocol (realme Link type 2) is Unsupported.

Usage:  python3 scripts/generate-catalog.py            (writes the Swift file)
        python3 scripts/generate-catalog.py --check    (exit 1 if the file is out of date)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "Documentation" / "ModelCatalog"
OUT = ROOT / "Sources" / "OneBudsCore" / "DeviceCatalog.swift"
TABLE = DATA / "Models.md"
ROWS = []  # (brand, name, product ids, status, features or reason, confidence) for Models.md

# Hand-written, hardware-backed or owner-specific profiles in DeviceRegistry.swift win over generated ones.
HAND_WRITTEN = {"063C14", "064414", "062012", "062412", "C1E2B1"}
SPEAKERS = {"Cobble Speaker", "Brick Speaker", "Pocket Speaker"}
VARIANTS = {"星光版": "Starlight", "丹拿版": "Dynaudio", "新声版": "New Sound", "轻享版": "Lite"}
MANUFACTURER = {"OnePlus": ".onePlus", "OPPO": ".oppo", "realme": ".realme", "DIZO": ".realme"}

ACTIONS = {"single": "single", "double": "double", "triple": "triple", "hold": "hold", "longHold": "longHold", "slide": "slide"}


def hex_bytes(text):
    text = str(text).replace("0x", "").replace(" ", "")
    if not text or len(text) % 2 or not re.fullmatch(r"[0-9A-Fa-f]+", text):
        return None
    return [int(text[i:i + 2], 16) for i in range(0, len(text), 2)]


def hex_int(text):
    if text is None:
        return None
    text = str(text).strip()
    if not re.fullmatch(r"(0x)?[0-9A-Fa-f]{1,4}", text):
        return None
    return int(text, 16)


def clean_name(name):
    name = re.sub(r"\s*[\(\[](?:modeType|S5|S4)[^\)\]]*[\)\]]", "", name)
    return name.strip()


def display_name(model):
    for chinese, english in VARIANTS.items():
        if chinese in model:
            return re.sub(r"[（(].*?[）)]", "", model).strip() + f" ({english})"
    return model.strip()


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.replace("+", " plus").lower()).strip("-")


USED_IDENTS, USED_SLUGS = set(), set()


def unique(value, pid, used):
    """Two catalogue rows can share a name (e.g. "Air3i" / "Air 3i"); the product id keeps them apart."""
    if value in used:
        value = f"{value}{pid}" if value.startswith("catalog") else f"{value}-{pid.lower()}"
    used.add(value)
    return value


def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def noise_option(mode, set_bytes, read_value):
    cases = {
        "off": ".off", "transparency": ".transparency", "adaptive": ".adaptive", "anc": ".noiseCancelling(nil)",
        "anc-smart": ".noiseCancelling(.smart)", "anc-deep": ".noiseCancelling(.deep)",
        "anc-medium": ".noiseCancelling(.medium)", "anc-light": ".noiseCancelling(.light)",
    }
    if mode not in cases:
        return None
    return f"NoiseModeOption({cases[mode]}, set: [{', '.join(f'0x{b:02X}' for b in set_bytes)}], read: 0x{read_value:04X})"


def noise_modes(model, notes):
    """Sourced set/read pairs. A plain-ANC entry without a read value gets one only from a
    documented rule: on the NC tree it reads 0x0002 like Buds 3 (hardware-verified); on the
    simple three-bit scheme (ANC 01, Off 02, Transparency 04) read == set (S5's 1<<index rule)."""
    entries = model.get("noiseModes") or []
    out, derived_simple, derived_tree = [], False, False
    tree = any(e.get("mode", "").startswith("anc-") for e in entries)
    simple = not tree and sorted(hex_int(e.get("setBytes")) or -1 for e in entries) == [0x01, 0x02, 0x04]
    for e in entries:
        set_bytes = hex_bytes(e.get("setBytes"))
        missing = e.get("readValue") is None  # a non-hex note (e.g. "level-dependent") is not missing: no guess
        read = hex_int(e.get("readValue"))
        if set_bytes is None:
            continue
        if read is None and missing and e.get("mode") == "anc" and set_bytes == [0x02] and tree:
            read, derived_tree = 0x0002, True
        elif read is None and missing and simple and len(set_bytes) == 1:
            read, derived_simple = set_bytes[0], True
        if read is None:
            continue
        option = noise_option(e.get("mode"), set_bytes, read)
        if option and option not in out:
            out.append(option)
    if derived_simple:
        notes.append("Noise read-back values follow S5's bit rule (read equals the set bit); not captured from this model.")
    if derived_tree:
        notes.append("Plain noise cancelling reads back as 0x0002 as on OnePlus Buds 3 (hardware-verified); not captured from this model.")
    return out


def gestures(model, brand):
    actions = ((model.get("gestures") or {}).get("actions")) or {}
    result = {}
    for key, codes in actions.items():
        if key not in ACTIONS or not codes:
            continue
        parsed = [hex_int(c) for c in codes]
        if None in parsed:
            continue
        result[ACTIONS[key]] = parsed
    return result


def feature_ids(model):
    ids = model.get("featureSwitchIDs") or {}
    out = {}
    for key in ["gameMode", "wearDetection", "dualConnection", "smartVolume", "bassWave", "spatialAudio", "goldenSound"]:
        value = hex_int(ids.get(key))
        # Power saving and Hi-Res are never offered (restart the buds / drop the link).
        if value is not None and value not in (0x05, 0x17, 0x18):
            out[key] = value
    return out


def sources_of(model):
    seen = []
    for value in (model.get("sources") or {}).values():
        for item in value if isinstance(value, list) else [value]:
            key = str(item).split()[0].rstrip(",;")
            if re.fullmatch(r"S\d+", key) and key not in seen:
                seen.append(key)
    return seen or ["S5"]


def classify(model, brand):
    """Returns 'control', 'unknown', 'unsupported' or None (skip)."""
    ids = model.get("productIDs") or []
    name = model.get("model", "")
    if not ids or any(s in name for s in SPEAKERS):
        return None
    if set(ids) & HAND_WRITTEN:
        return None
    if model.get("protocol") == "realmeLinkType2":
        return "unsupported"
    transports = model.get("transports") or {}
    if transports.get("legacy1107"):
        return "unknown"
    on_opo = transports.get("rfcomm079A") or transports.get("spp1101")
    if not on_opo:
        return "unsupported" if brand == "OPPO" and "no-SPP" in (model.get("notes") or "") else "unknown"
    if (model.get("noiseModes") or model.get("eqPresets")) and str(model.get("confidence", "")).split()[0] in ("high", "medium", "medium-high"):
        return "control"
    return "unknown"


def control_profile(model, brand):
    notes = []
    pid = model["productIDs"]
    name = display_name(model["model"])
    transports = model.get("transports") or {}
    ble = brand == "OnePlus" and transports.get("bleGATT079A") is True
    rfcomm = "[opoService, standardSPP]" if brand == "realme" else "[opoService]"
    modes = noise_modes(model, notes)
    eq = []
    for e in model.get("eqPresets") or []:
        if isinstance(e.get("id"), int) and e.get("name"):
            minimum = f", minimumFirmware: {e['minFirmware']}" if isinstance(e.get("minFirmware"), int) else ""
            eq.append(f"EQPresetOption(id: {e['id']}, name: {swift_string(clean_name(e['name']))}{minimum})")
    feats = feature_ids(model)
    gest = gestures(model, brand)
    hearing = brand == "OnePlus" and model.get("hearingTest") is True and "goldenSound" in feats
    if not hearing:
        feats.pop("goldenSound", None)
    finds = model.get("findEarbuds") is True
    fit = brand == "OnePlus" and model.get("fitTest") is True
    bass = None
    if isinstance(model.get("bassLevels"), str):
        match = re.fullmatch(r"\s*([+-]?\d+)\s*\.\.\.\s*\+?(-?\d+)\s*", model["bassLevels"])
        if match:
            bass = (int(match.group(1)), int(match.group(2)))
    ceq = model.get("customEQ") or {}
    custom = None
    if brand == "OnePlus" and ceq.get("bands") and ceq.get("maxGainDb"):
        presets = ceq.get("maxPresets") or 3  # S4's documented default limit
        custom = f"CustomEQLayout(frequencies: {list(ceq['bands'])}, maximumGain: {ceq['maxGainDb']}, maximumPresets: {presets})"
    cycle = model.get("noiseCycleBits")

    caps = ["battery", "deviceInfo"]
    if modes: caps.append("noiseControl")
    if eq: caps.append("equalizer")
    if gest: caps.append("gestures")
    for key in ["gameMode", "wearDetection", "dualConnection", "smartVolume", "bassWave", "spatialAudio"]:
        if key in feats: caps.append(key)
    if custom: caps.append("customEqualizer")
    if cycle: caps.append("noiseCycle")
    if finds: caps.append("findEarbuds")
    if fit: caps.append("fitTest")
    if hearing: caps.append("hearingTest")

    args = [f"productIDs: [{', '.join(swift_string(p) for p in pid)}]"]
    if modes: args.append("noiseModes: [\n                " + ",\n                ".join(modes) + "]")
    if eq: args.append("equalizerPresets: [" + ", ".join(eq) + "]")
    status_ids = sorted(set(feats.values()))
    if status_ids: args.append("featureStatusIDs: [" + ", ".join(f"0x{i:02X}" for i in status_ids) + "]")
    for key, label in [("gameMode", "gameModeFeatureID"), ("wearDetection", "wearDetectionFeatureID"), ("dualConnection", "dualConnectionFeatureID")]:
        if key in feats: args.append(f"{label}: 0x{feats[key]:02X}")
    if gest:
        args.append("gestureFunctions: [" + ", ".join(
            f"GestureAction.{a}.rawValue: [{', '.join(f'0x{c:02X}' for c in codes)}]" for a, codes in gest.items()) + "]")
        if brand == "realme":
            args.append('gestureFunctionNames: [0x04: "Voice assistant", 0x03: "Function 0x03"]')
    for key, label in [("smartVolume", "smartVolumeFeatureID"), ("bassWave", "bassWaveFeatureID"), ("spatialAudio", "spatialAudioFeatureID"), ("goldenSound", "goldenSoundFeatureID")]:
        if key in feats: args.append(f"{label}: 0x{feats[key]:02X}")
    if cycle: args.append("noiseCycleBits: [" + ", ".join(f".{k}: {v}" for k, v in cycle.items()) + "]")
    if custom: args.append(f"customEQ: {custom}")
    if bass: args.append(f"bassLevels: {bass[0]}...{bass[1]}")
    if finds: args.append("findsEarbuds: true")
    if fit: args.append("runsFitTest: true")
    if hearing: args.append("runsHearingTest: true")

    confidence = str(model.get("confidence") or "unknown")
    ROWS.append((brand, name, pid, "🟡 Experimental", ", ".join(CAP_NAMES[c] for c in caps if c not in ("battery", "deviceInfo")), confidence.split()[0]))
    limitations = [f"Experimental: built from published protocol data (confidence: {confidence}); not yet tested with OneBuds."]
    limitations += notes
    for conflict in (model.get("conflicts") or [])[:3]:
        text = re.sub(r"\s+", " ", str(conflict))
        if len(text) > 320:
            text = text[:320].rsplit(" ", 1)[0] + "…"
        limitations.append("Sources disagree: " + text)
    names = model.get("bluetoothNames") or ([] if any(c in model["model"] for c in VARIANTS) else [name])
    return model["_ident"], f"""
    static let {model["_ident"]} = DeviceProfile(
        id: {swift_string(model["_slug"])}, manufacturer: {MANUFACTURER[brand]}, model: {swift_string(name)}, displayName: {swift_string(name)},
        bluetoothNames: [{', '.join(swift_string(n) for n in names)}],
        transports: {"[.ble, .rfcomm]" if ble else "[.rfcomm]"}, rfcommServiceUUIDs: {rfcomm}, ble: {"opoBLE" if ble else "nil"},
        protocolKind: .opoV1,
        opo: OPOParameters(
            {(",\n            ").join(args)}),
        status: .experimental,
        capabilities: [{', '.join(f'.{c}: .experimental' for c in caps)}],
        testedFirmware: [],
        limitations: [
            {(",\n            ").join(swift_string(l) for l in limitations)},
        ],
        sources: [{', '.join(swift_string(s) for s in sources_of(model))}], evidence: [])
"""


def swift_ident(name):
    words = re.findall(r"[A-Za-z0-9]+", name.replace("+", " Plus"))
    ident = words[0].lower() + "".join(w[:1].upper() + w[1:] for w in words[1:])
    return "catalog" + ident[:1].upper() + ident[1:]


CAP_NAMES = {"noiseControl": "noise control", "equalizer": "EQ", "gestures": "gestures", "gameMode": "game mode",
             "wearDetection": "in-ear detection", "dualConnection": "dual connection", "smartVolume": "smart volume",
             "bassWave": "BassWave", "spatialAudio": "3D audio", "customEqualizer": "custom EQ", "noiseCycle": "noise cycle",
             "findEarbuds": "find earbuds", "fitTest": "fit test", "hearingTest": "Golden Sound"}


def other_profile(model, brand, kind):
    name = display_name(model["model"])
    pid = model["productIDs"][0]
    transports = model.get("transports") or {}
    ROWS.append((brand, name, model["productIDs"], "🔴 Unsupported" if kind == "unsupported" else "⚪ Diagnostics only",
                 "legacy 1107 service" if transports.get("legacy1107") else ("non-OPO protocol" if model.get("protocol") == "realmeLinkType2" else "no published values"),
                 str(model.get("confidence") or "").split()[0] if model.get("confidence") else ""))
    if kind == "unsupported":
        why = ("Uses realme's older non-OPO protocol (realme Link type 2), which no source documents."
               if model.get("protocol") == "realmeLinkType2" else "The vendor catalogue lists no control channel for this model (S5).")
        return (f"        DeviceProfile(id: {swift_string(model['_slug'])}, manufacturer: {MANUFACTURER[brand]}, model: {swift_string(name)}, "
                f"displayName: {swift_string(name)}, bluetoothNames: [{swift_string(name)}], transports: [.rfcomm], "
                f"rfcommServiceUUIDs: [], ble: nil, protocolKind: .opoV1, opo: nil, status: .unsupported, capabilities: [:], "
                f"testedFirmware: [], limitations: [{swift_string(why)}], sources: [{', '.join(swift_string(s) for s in sources_of(model))}], evidence: []),")
    note = ("Uses the legacy 1107 service, whose handshake OneBuds does not implement yet."
            if transports.get("legacy1107") else "Listed by the vendor catalogue; no protocol values published yet.")
    return (f"        unknown({swift_string(model['_slug'])}, {MANUFACTURER[brand]}, {swift_string(name)}, "
            f"productID: {swift_string(pid)}, note: {swift_string(note)}),")


def generate():
    controls, others, seen_ids, seen_names = [], [], set(), set()
    for brand, file in [("OnePlus", "oneplus.json"), ("OPPO", "oppo.json"), ("realme", "realme.json")]:
        for model in json.loads((DATA / file).read_text()):
            kind = classify(model, "DIZO" if model["model"].startswith("DIZO") else brand)
            if kind is None:
                continue
            # Product ids may be shared by different models (OPPO Enco Buds2 reports realme Buds Q2s'
            # 060C12): keep them on both, so DeviceRegistry.match never picks either by id alone.
            ids = list(model["productIDs"])
            name = display_name(model["model"])
            if name in seen_names:
                continue  # the same model listed twice
            model = dict(model, productIDs=ids, _ident=unique(swift_ident(name), ids[0], USED_IDENTS),
                         _slug=unique(slug(name), ids[0], USED_SLUGS))
            seen_ids.update(ids)
            seen_names.add(name)
            b = "DIZO" if model["model"].startswith("DIZO") else brand
            if kind == "control":
                controls.append(control_profile(model, b))
            else:
                others.append(other_profile(model, b, kind))
    body = "".join(p for _, p in controls)
    return f"""// Generated by scripts/generate-catalog.py from Documentation/ModelCatalog/*.json. Do not edit by hand:
// change the JSON (with its sources) and run the script again.
import Foundation

extension DeviceRegistry {{
    /// Models with published OPOv1 values: control sessions, every capability Experimental.
    static let catalogControlProfiles: [DeviceProfile] = [
        {(",\n        ").join(i for i, _ in controls)},
    ]

    /// Models recognised for diagnostics only, or known not to speak OPOv1.
    static let catalogOtherProfiles: [DeviceProfile] = [
{chr(10).join(others)}
    ]
{body}}}
"""


def table():
    lines = ["# Earbud model catalogue", "",
             "Generated by `scripts/generate-catalog.py` from the JSON files in this folder. Every value in them",
             "cites its sources (see ../ProtocolSources.md); nothing is inferred. Hand-written, hardware-backed",
             "profiles (OnePlus Buds 3, Nord Buds 3 Pro, realme Buds Air 5 and T300, Wireless 2) live in",
             "DeviceRegistry.swift and are not listed here.", "",
             "Experimental models get a control session; each feature appears only if its protocol values are",
             "published, and the earbuds' own capability list can still hide it. The product id the earbuds",
             "report decides the profile, so special editions sharing a name are handled.", "",
             "| Brand | Model | Product id | Status | Features offered / reason | Source confidence |", "|---|---|---|---|---|---|"]
    for brand, name, pid, status, features, confidence in sorted(ROWS, key=lambda r: (r[0], r[3], r[1])):
        lines.append(f"| {brand} | {name} | {' / '.join(f'`{p}`' for p in pid)} | {status} | {features or '—'} | {confidence} |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    text = generate()
    markdown = table()
    if "--check" in sys.argv:
        fresh = OUT.exists() and OUT.read_text() == text and TABLE.exists() and TABLE.read_text() == markdown
        sys.exit(0 if fresh else 1)
    OUT.write_text(text)
    TABLE.write_text(markdown)
    print(f"Wrote {OUT.relative_to(ROOT)} and {TABLE.relative_to(ROOT)}")
