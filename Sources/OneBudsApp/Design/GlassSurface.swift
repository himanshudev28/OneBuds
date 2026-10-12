import SwiftUI

/// Background for a card or control. Standard: a quiet system fill. Glass: real Liquid Glass when
/// available (macOS 26 SDK + runtime), otherwise a translucent fill with a light top edge and soft
/// shadow. No blur is stacked on blur. Reduce Transparency always gets the standard fill.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.visualStyle) private var visualStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let standardFill: AnyShapeStyle
    /// A solid tint (e.g. the accent for a selected control) drawn under the glass highlights.
    var tint: Color?

    private var usesGlass: Bool { visualStyle == .glass && !reduceTransparency }
    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        if usesGlass {
            glass(content)
        } else {
            content.background(shape.fill(tint.map { AnyShapeStyle($0) } ?? standardFill))
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            approximatedGlass(content)
        }
        #else
        approximatedGlass(content)
        #endif
    }

    private func approximatedGlass(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.white.opacity(isDark ? 0.07 : 0.5)))
                    // Light catching the top of the material.
                    shape.fill(LinearGradient(colors: [.white.opacity(isDark ? 0.10 : 0.35), .clear],
                                              startPoint: .top, endPoint: .center))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(isDark ? 0.32 : 0.9), .white.opacity(isDark ? 0.04 : 0.25)],
                                                  startPoint: .top, endPoint: .bottom),
                                   lineWidth: 1)
            }
            .shadow(color: .black.opacity(isDark ? 0.28 : 0.08), radius: 8, y: 2)
    }
}

extension View {
    func surface<S: InsettableShape>(_ shape: S, standardFill: some ShapeStyle = .quinary, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: shape, standardFill: AnyShapeStyle(standardFill), tint: tint))
    }
}
