import OneBudsCore
import SwiftUI

/// One EQ preset. The check marks the preset the earbuds confirmed; a spinner marks the request.
struct EqualizerPresetCard: View {
    let preset: EQPresetOption
    let isSelected: Bool
    let isPending: Bool
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous) }

    private var border: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(contrast == .increased ? 1 : 0.6)) }
        return contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.clear)
    }

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
            .surface(shape, standardFill: fill)
            .overlay {
                shape.strokeBorder(border, lineWidth: Theme.Stroke.hairline)
            }
            .contentShape(shape)
            .focusRing(shape, isFocused: isFocused)
        }
        .buttonStyle(.pressable)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .accessibilityLabel(preset.name)
        .accessibilityValue(isSelected ? "Selected" : isPending ? "Applying" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
