import SwiftUI

/// Round device glyph: accent when connected, neutral otherwise.
struct DeviceIcon: View {
    let isConnected: Bool
    let diameter: CGFloat

    var body: some View {
        Image(systemName: isConnected ? "earbuds" : "earbuds.case")
            .font(diameter > 40 ? .title : .callout)
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: diameter, height: diameter)
            .background(isConnected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.35)), in: Circle())
            .accessibilityHidden(true)
    }
}
