import OneBudsCore
import SwiftUI

/// One noise-control option. The accent fill marks the mode the earbuds *confirmed*; a requested
/// mode shows a native spinner until they do.
struct NoiseModeButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let category: NoiseCategory
    let isSelected: Bool
    let isPending: Bool
    let large: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false

    private var diameter: CGFloat { large ? Theme.Size.modeButtonLarge : Theme.Size.modeButton }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s - 2) {
                ZStack {
                    Color.clear
                        .surface(Circle(), standardFill: isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
                    if isSelected {
                        selectionFill
                    }
                    Image(systemName: category.symbolName)
                        .font(large ? .title2 : .title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .frame(width: diameter, height: diameter)

                Text(category.displayName)
                    .font(large ? .callout : .caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .accessibilityLabel(category.menuTitle)
        .accessibilityValue(isSelected ? "Selected" : isPending ? "Applying" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isPending ? "Waiting for the earbuds to confirm" : category.explanation)
    }

    @ViewBuilder
    private var selectionFill: some View {
        // The highlight slides between options; under Reduce Motion it cross-fades in place.
        if reduceMotion {
            Color.clear.surface(Circle(), tint: .accentColor)
        } else {
            Color.clear.surface(Circle(), tint: .accentColor).matchedGeometryEffect(id: "selection", in: namespace)
        }
    }
}
