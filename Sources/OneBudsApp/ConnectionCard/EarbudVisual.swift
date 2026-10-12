import AppKit
import SwiftUI

/// The device picture on the connection card. In order: the licensed 3D model (RealityKit), the
/// licensed product render, then the generic earbud glyph. A file that fails to load falls through
/// to the next. The glyph is deliberately abstract: it never stands in for a specific product.
struct EarbudVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let artwork: EarbudArtwork
    let size: CGFloat
    /// Settings ▸ Connection Card ▸ Gently rotate 3D model; Reduce Motion always holds it still.
    var animates = true
    @State private var modelFailed = false
    /// Rest-pose snapshot used instead of the live 3D view while the model is held still.
    @State private var still: NSImage?

    private var sways: Bool { animates && !reduceMotion }

    private var renderImage: NSImage? { artwork.render.flatMap(NSImage.init(contentsOf:)) }

    var body: some View {
        Group {
            if let model = artwork.model, !modelFailed {
                if let still, !sways {
                    Image(nsImage: still)
                        .resizable()
                        .scaledToFit()
                } else {
                    EarbudModelView(url: model, animates: sways,
                                    onFailure: { modelFailed = true },
                                    onStill: { still = $0 })
                }
            } else if let image = renderImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.04)
            } else {
                EarbudGlyph(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: artwork) {
            modelFailed = false
            still = nil
        }
    }
}

/// Fallback artwork: the system earbuds-and-case symbol on an accent tile with a soft glow. It
/// bounces once when the card appears (not under Reduce Motion).
struct EarbudGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat
    @State private var arrivals = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(0.32), .clear],
                                     center: .center, startRadius: 0, endRadius: size / 2))
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.accentColor.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .frame(width: size * 0.7, height: size * 0.7)
                .shadow(color: Color.accentColor.opacity(0.35), radius: size * 0.08, y: size * 0.04)
            Image(systemName: "earbuds.case.fill")
                .font(.system(size: size * 0.32, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: arrivals)
        }
        .frame(width: size, height: size)
        .onAppear { if !reduceMotion { arrivals += 1 } }
    }
}

/// Hosts `EarbudSceneView` (RealityKit `ARView`, macOS 10.15+, so it also works on macOS 14).
private struct EarbudModelView: NSViewRepresentable {
    let url: URL
    let animates: Bool
    let onFailure: () -> Void
    let onStill: (NSImage) -> Void

    func makeNSView(context: Context) -> EarbudSceneView {
        let view = EarbudSceneView(frame: .zero)
        view.animates = animates
        view.onFailure = onFailure
        view.onStill = onStill
        view.load(url)
        return view
    }

    func updateNSView(_ view: EarbudSceneView, context: Context) {
        view.animates = animates
    }

    static func dismantleNSView(_ view: EarbudSceneView, coordinator: ()) {
        view.tearDown()
    }
}
