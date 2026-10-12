import SwiftUI

struct AppearanceSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                FormFooter("System follows your Mac's Light or Dark setting. The menu-bar icon always matches the menu bar.")
            }

            Section {
                Picker("Style", selection: $settings.visualStyle) {
                    ForEach(VisualStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if reduceTransparency && settings.visualStyle == .glass {
                    Label("Reduce Transparency is on, so OneBuds shows the standard style.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                FormFooter(Self.glassNote)
            }
        }
        .settingsPaneStyle()
    }

    private static var glassNote: String {
        if #available(macOS 26.0, *) {
            return "Glass uses translucent surfaces that let your desktop show through. Real Liquid Glass is used when OneBuds is built with the macOS 26 SDK."
        }
        return "Glass uses translucent surfaces that let your desktop show through. Real Liquid Glass needs macOS 26 or later; this Mac gets a close approximation."
    }
}
