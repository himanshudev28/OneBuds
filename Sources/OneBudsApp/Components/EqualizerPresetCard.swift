import OneBudsCore
import SwiftUI

/// One EQ preset. The check marks the preset the earbuds confirmed; a spinner marks the request.
struct EqualizerPresetCard: View {
    let preset: EQPresetOption
    let isSelected: Bool
    let isPending: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var fill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        return isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m - 2) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                Text(preset.name)
                    .font(.callout)
                    .bold(isSelected)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                if isPending {
                    ProgressView().controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(RoundedRectangle(cornerRadius: Theme.Radius.control + 2), standardFill: fill)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control + 2)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .accessibilityLabel(preset.name)
        .accessibilityValue(isSelected ? "Selected" : isPending ? "Applying" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
