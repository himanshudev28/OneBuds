import OneBudsCore
import SwiftUI

/// Popover noise-control option: a round button with its name underneath, like Control Center.
/// The accent fill marks the mode the earbuds confirmed and glides between options; the icon
/// gives one small bounce when its mode is confirmed.
struct NoiseModeCircle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let category: NoiseCategory
    let isSelected: Bool
    let isPending: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private static let selectionColor = Color(nsColor: .selectedContentBackgroundColor)

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xsPlus) {
                ZStack {
                    Circle().fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
                    if isSelected { selection }
                    if isPending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: category.symbolName)
                            .font(.system(size: Theme.Size.noiseSymbol, weight: .medium))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : isSelected)
                    }
                }
                .frame(width: Theme.Size.noiseCircle, height: Theme.Size.noiseCircle)
                .overlay {
                    if contrast == .increased { Circle().strokeBorder(.secondary, lineWidth: Theme.Stroke.hairline) }
                }
                .focusRing(Circle(), isFocused: isFocused)

                Text(category.popoverTitle)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .accessibilityLabel(category.menuTitle)
        .accessibilityValue(isSelected ? "Selected" : isPending ? "Applying" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isPending ? "Waiting for the earbuds to confirm" : category.explanation)
    }

    @ViewBuilder
    private var selection: some View {
        if reduceMotion {
            Circle().fill(Self.selectionColor)
        } else {
            Circle().fill(Self.selectionColor.gradient).matchedGeometryEffect(id: "noise-selection", in: namespace)
        }
    }
}

extension NoiseCategory {
    /// Labels under the popover's round buttons, as short as the system's own.
    var popoverTitle: String {
        switch self {
        case .noiseCancelling: "Noise Cancel"
        default: displayName
        }
    }
}
