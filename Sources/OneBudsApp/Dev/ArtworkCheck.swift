import AppKit
import OneBudsCore

/// Development aid: when `ONEBUDS_ARTWORK_CHECK` is set to a directory, renders every bundled
/// `EarbudAssets/*.usdz` (or the file in `ONEBUDS_ARTWORK_FIXTURE`) through the card's
/// `EarbudSceneView` to PNGs at rest and mid-sway, composited on light and dark card colours, and
/// writes `artwork-check.txt` (load result, transparent background, fallback on a broken file).
/// The window appears briefly at the bottom left of the screen: Metal only renders on screen.
@MainActor
enum ArtworkCheck {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["ONEBUDS_ARTWORK_CHECK"].map { URL(fileURLWithPath: $0) }
    }

    static func run(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines: [String] = []
        var files: [URL] = []
        if let fixture = ProcessInfo.processInfo.environment["ONEBUDS_ARTWORK_FIXTURE"] {
            files.append(URL(fileURLWithPath: fixture))
        } else if let folder = Bundle.main.resourceURL?.appendingPathComponent(EarbudArtwork.folder) {
            files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "usdz" }
        }
        if files.isEmpty { lines.append("No .usdz artwork bundled: the card falls back to a product image or the symbol.") }

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let (view, window) = makeScene()
            view.animates = false
            var failed = false
            var stillPixels: Int?
            view.onFailure = { failed = true }
            view.onStill = { image in stillPixels = image.representations.map(\.pixelsWide).max() }
            view.load(file)
            _ = await waitUntil(timeout: .seconds(10)) { view.isLoaded || failed }
            _ = await waitUntil(timeout: .seconds(2)) { stillPixels != nil }
            guard view.isLoaded else {
                lines.append("\(name): FAILED to load")
                window.orderOut(nil)
                continue
            }
            try? await Task.sleep(for: .milliseconds(600))
            let rest = await snapshot(view)
            view.animates = true
            view.advance(by: EarbudSceneView.easeIn + EarbudSceneView.swayPeriod / 4)
            try? await Task.sleep(for: .milliseconds(300))
            let swayed = await snapshot(view)
            window.orderOut(nil)

            lines.append("\(name): loaded; transparent background: \(rest.map { hasTransparentCorners($0) } ?? false)")
            lines.append("  still snapshot for Reduce Motion / rotation off: \(stillPixels.map { "\($0) px wide for a 288 pt view" } ?? "none")")
            for (label, image) in [("rest", rest), ("sway", swayed)] {
                guard let image else { lines.append("  \(label): snapshot failed"); continue }
                for (scheme, colour) in [("light", NSColor(white: 0.93, alpha: 1)), ("dark", NSColor(white: 0.17, alpha: 1))] {
                    write(composite(image, on: colour), to: directory.appendingPathComponent("artwork-\(name)-\(label)-\(scheme).png"))
                }
            }
        }

        // A broken file must hand over to the next artwork rather than leave a blank square.
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("onebuds-broken.usdz")
        try? Data("not a usdz".utf8).write(to: broken)
        let (view, window) = makeScene()
        var fellBack = false
        view.onFailure = { fellBack = true }
        view.load(broken)
        _ = await waitUntil(timeout: .seconds(5)) { fellBack }
        window.orderOut(nil)
        lines.append("broken .usdz falls back: \(fellBack)")

        try? (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("artwork-check.txt"), atomically: true, encoding: .utf8)
        exit(0)
    }

    private static func makeScene() -> (EarbudSceneView, NSWindow) {
        let side: CGFloat = 288
        let view = EarbudSceneView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let window = NSWindow(contentRect: CGRect(x: 20, y: 20, width: side, height: side), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        window.orderFrontRegardless()
        return (view, window)
    }

    private static func snapshot(_ view: EarbudSceneView) async -> NSImage? {
        // Hand the pixels over as Data: NSImage is not Sendable.
        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0?.tiffRepresentation) }
        }
        return data.flatMap(NSImage.init(data:))
    }

    private static func hasTransparentCorners(_ image: NSImage) -> Bool {
        guard let rep = image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init(cgImage:)) else { return false }
        let corners = [(0, 0), (rep.pixelsWide - 1, 0), (0, rep.pixelsHigh - 1), (rep.pixelsWide - 1, rep.pixelsHigh - 1)]
        return corners.allSatisfy { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 1) < 0.02 }
    }

    private static func composite(_ image: NSImage, on colour: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            colour.setFill()
            rect.fill()
            image.draw(in: rect)
            return true
        }
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
