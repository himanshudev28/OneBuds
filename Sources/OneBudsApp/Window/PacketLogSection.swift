import OneBudsCore
import SwiftUI

/// Opt-in, in-memory raw packet log.
struct PacketLogSection: View {
    @Environment(DeviceManager.self) private var manager

    var body: some View {
        @Bindable var manager = manager
        Section {
            Toggle("Record raw packets (kept in memory only)", isOn: $manager.isPacketLoggingEnabled)
            if manager.isPacketLoggingEnabled {
                if manager.packetLog.isEmpty {
                    Text("No packets yet. Use a control or Refresh.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            ForEach(manager.packetLog.reversed()) { entry in
                                Text("\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.direction.rawValue)  \(entry.summary)  [\(entry.hex)]")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(entry.direction == .sent ? Color.accentColor : .primary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.s)
                    }
                    .frame(minHeight: 180, maxHeight: 360)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
            }
        } header: {
            Text("Packet Log")
        } footer: {
            FormFooter("Device lists that contain other devices' names or addresses are always redacted.")
        }
    }
}
