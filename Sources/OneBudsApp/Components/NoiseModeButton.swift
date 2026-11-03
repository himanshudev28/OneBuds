import AppKit
import OneBudsCore
import SwiftUI

/// One noise-control option as an equal-width tile. The accent fill marks the mode the earbuds
/// *confirmed*; a requested mode shows a native spinner in place of its icon until they do.
struct NoiseModeButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let category: NoiseCategory
    let isSelected: Bool
    let isPending: Bool
    let large: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    /// Derived from the accent but tuned by macOS for white text, so a yellow or green accent stays legible.
    private static let selectionColor = Color(nsColor: .selectedContentBackgroundColor)

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous) }

    /// The tile says "Noise Cancelling" where there is room; the popover uses the short "ANC".
    private var title: String { large ? category.menuTitle : category.displayName }

    var body: some View {
        Button(action: action) {
            VStack(spacing: large ? Theme.Spacing.xsPlus : Theme.Spacing.xs) {
                // A fixed slot, so labels share a baseline whatever each symbol's height.
                Image(systemName: category.symbolName)
                    .font(.system(size: iconSize, weight: .medium))
                    .frame(height: iconSize * 1.35)
                    .foregroundStyle(glyphStyle)
                    .opacity(isPending ? 0 : 1)
                    .overlay {
                        if isPending { ProgressView().controlSize(.small) }
                    }
                Text(title)
                    .font(large ? .subheadline : .caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected && !large ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: large ? Theme.Tile.heightWindow : Theme.Tile.heightCompact)
            .background {
                if large {
                    // Window: quiet fill; the selected tile gets a light accent tint and hairline.
                    ZStack {
                        shape.fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
                        if isSelected { windowSelection }
                    }
                } else {
                    ZStack {
                        Color.clear.surface(shape, standardFill: isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
                        if isSelected { selectionFill }
                    }
                }
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary), lineWidth: Theme.Stroke.hairline)
                }
            }
            .contentShape(shape)
            .focusRing(shape, isFocused: isFocused)
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

    private var glyphStyle: AnyShapeStyle {
        if !isSelected { return AnyShapeStyle(.primary) }
        return large ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white)
    }

    private var iconSize: CGFloat {
        large ? Theme.Tile.iconWindow : Theme.Tile.iconCompact
    }

    @ViewBuilder
    private var windowSelection: some View {
        let base = ZStack {
            shape.fill(Color.accentColor.opacity(contrast == .increased ? 0.24 : 0.15))
            shape.strokeBorder(Color.accentColor.opacity(0.6), lineWidth: Theme.Stroke.hairline)
        }
        if reduceMotion {
            base
        } else {
            base.matchedGeometryEffect(id: "selection", in: namespace)
        }
    }

    @ViewBuilder
    private var selectionFill: some View {
        // The highlight slides between tiles; under Reduce Motion it cross-fades in place.
        if reduceMotion {
            Color.clear.surface(shape, tint: Self.selectionColor)
        } else {
            Color.clear.surface(shape, tint: Self.selectionColor).matchedGeometryEffect(id: "selection", in: namespace)
        }
    }
}
