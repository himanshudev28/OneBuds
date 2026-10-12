import AppKit
import Combine
import os
import RealityKit

/// RealityKit view for one earbud model on the connection card.
///
/// - Framing: the model is centred and scaled so its widest swept extent fills ~85% of the view.
/// - Lighting: the default image-based light plus a soft key from the upper left and a rim from
///   behind, so edges read on both light and dark cards.
/// - Motion: a slow sway of about ±20° around a three-quarter pose that eases in from rest, rather
///   than a full turntable. `animates = false` (or Reduce Motion) holds the rest pose and hands a
///   snapshot to `onStill`, so the card can drop the live Metal view (ARView cannot pause).
/// - Transparent background, no camera controls: it is a picture, not a viewer.
@MainActor
final class EarbudSceneView: ARView {
    var animates = true {
        didSet {
            guard animates != oldValue, isLoaded else { return }
            animates ? startSway() : holdStill()
        }
    }
    /// Called (asynchronously) if the file cannot be loaded, so the card can fall back.
    var onFailure: (() -> Void)?
    /// Called with a snapshot of the rest pose once the model is loaded and held still.
    var onStill: ((NSImage) -> Void)?
    /// Set once the model has been added to the scene (used by the artwork check).
    private(set) var isLoaded = false

    static let restingYaw: Float = -.pi / 6
    static let swayAmplitude: Float = 0.35
    static let swayPeriod: TimeInterval = 10
    static let easeIn: TimeInterval = 1.5
    static let fieldOfView: Float = 28
    static let fill: Float = 0.85
    private static var restOrientation: simd_quatf { simd_quatf(angle: restingYaw, axis: [0, 1, 0]) }
    private static let logger = Logger(subsystem: "com.local.onebuds", category: "artwork")

    private let anchor = AnchorEntity(world: .zero)
    private let pivot = Entity()
    private var updates: (any Cancellable)?
    private var loading: AnyCancellable?
    private var elapsed: TimeInterval = 0

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        environment.background = .color(.clear)
        pivot.orientation = Self.restOrientation
        anchor.addChild(pivot)
        anchor.addChild(Self.camera())
        for light in Self.lights() { anchor.addChild(light) }
        scene.addAnchor(anchor)
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func load(_ url: URL) {
        if #available(macOS 15.0, *) {
            Task {
                do {
                    try present(try await Entity(contentsOf: url), from: url)
                } catch {
                    fail(url, error)
                }
            }
        } else {
            loading = Entity.loadAsync(contentsOf: url).sink { [weak self] completion in
                if case .failure(let error) = completion { self?.fail(url, error) }
            } receiveValue: { [weak self] model in
                do { try self?.present(model, from: url) } catch { self?.fail(url, error) }
            }
        }
    }

    /// Stops all work; called when the card removes the view.
    func tearDown() {
        loading?.cancel()
        updates?.cancel()
        updates = nil
        onFailure = nil
        onStill = nil
        scene.anchors.removeAll()
    }

    private func present(_ model: Entity, from url: URL) throws {
        guard Self.fit(model) else { throw CocoaError(.fileReadCorruptFile) }
        pivot.addChild(model)
        isLoaded = true
        animates ? startSway() : holdStill()
        Self.logger.info("Loaded 3D artwork \(url.lastPathComponent, privacy: .public)")
    }

    private func fail(_ url: URL, _ error: any Error) {
        Self.logger.error("Could not load 3D artwork \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        // Never inside a SwiftUI update pass.
        Task { @MainActor [weak self] in self?.onFailure?() }
    }

    /// Advances the sway by `seconds` (the scene's frame time; also used by the artwork check).
    func advance(by seconds: TimeInterval) {
        guard animates else { return }
        elapsed += seconds
        let t = min(1, elapsed / Self.easeIn)
        let ramp = Float(t * t * (3 - 2 * t))
        let sway = Float(sin(2 * .pi * elapsed / Self.swayPeriod))
        pivot.orientation = simd_quatf(angle: Self.restingYaw + Self.swayAmplitude * ramp * sway, axis: [0, 1, 0])
    }

    private func startSway() {
        elapsed = 0
        updates?.cancel()
        updates = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let delta = event.deltaTime
            MainActor.assumeIsolated { self?.advance(by: delta) }
        }
    }

    private func holdStill() {
        updates?.cancel()
        updates = nil
        elapsed = 0
        pivot.orientation = Self.restOrientation
        guard onStill != nil else { return }
        Task { @MainActor [weak self] in
            // Let one frame render in the rest pose first.
            try? await Task.sleep(for: .milliseconds(120))
            self?.snapshot(saveToHDR: false) { image in
                guard let self, let image, !self.animates else { return }
                self.onStill?(image)
            }
        }
    }

    /// Centres the model on the origin and scales it so that, while it sways, its larger half-size
    /// (horizontal diagonal or height) is 0.5. Returns false for an empty model.
    private static func fit(_ model: Entity) -> Bool {
        let bounds = model.visualBounds(relativeTo: nil)
        let horizontal = simd_length(SIMD2(bounds.extents.x, bounds.extents.z)) / 2
        let half = max(horizontal, bounds.extents.y / 2)
        guard half > 0, half.isFinite else { return false }
        let scale = 0.5 / half
        model.scale *= scale
        model.position = (model.position - bounds.center) * scale
        return true
    }

    private static func camera() -> PerspectiveCamera {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = fieldOfView
        // Distance at which a half-size of 0.5 fills `fill` of the view, seen from slightly above.
        let distance = 0.5 / tan(fieldOfView / 2 * .pi / 180) / fill
        let elevation: Float = .pi / 14
        camera.look(at: .zero, from: [0, distance * sin(elevation), distance * cos(elevation)], relativeTo: nil)
        return camera
    }

    private static func lights() -> [Entity] {
        let key = DirectionalLight()
        key.light.intensity = 1800
        key.look(at: .zero, from: [-1.4, 2.2, 1.8], relativeTo: nil)
        let rim = DirectionalLight()
        rim.light.intensity = 1400
        rim.look(at: .zero, from: [1.6, 0.9, -2.0], relativeTo: nil)
        return [key, rim]
    }
}
