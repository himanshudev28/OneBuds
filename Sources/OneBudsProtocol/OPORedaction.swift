/// Frames whose payload carries personal data that logs and exports must never show.
public enum OPORedaction {
    /// Observed 2026-10-12 on OnePlus Buds 3: push `0x0204` event `06` (multi-device list) carries the
    /// Bluetooth addresses and user-chosen names of the buds' other paired devices; the `0x8112`
    /// multi-device reply has the same content (documented by S10).
    public static func containsPersonalData(_ frame: OPOFrame) -> Bool {
        (frame.command == 0x0204 && frame.payload.first == 0x06) || frame.command == 0x8112
    }
}
