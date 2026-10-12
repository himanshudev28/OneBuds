import Foundation

/// Product artwork for one earbud model, looked up by profile id in the app bundle's
/// `Resources/EarbudAssets` folder (copied from `Packaging/EarbudAssets` by `scripts/build-app.sh`):
/// `<profile-id>.usdz` is a 3D model, `<profile-id>.png` or `.heic` a product render.
///
/// The card uses the model, else the render, else the generic glyph; a file that fails to load
/// falls through to the next. Only licensed artwork of that exact model belongs there. None ships
/// today, so every model currently shows the glyph.
struct EarbudArtwork: Equatable {
    var model: URL?
    var render: URL?

    static let none = EarbudArtwork()
    static let folder = "EarbudAssets"

    var summary: String {
        switch (model, render) {
        case (.some, .some): "3D model and product image installed"
        case (.some, nil): "3D model installed"
        case (nil, .some): "Product image installed"
        case (nil, nil): "No licensed artwork installed"
        }
    }

    static func lookup(profileID: String?, in bundle: Bundle = .main) -> EarbudArtwork {
        guard let profileID else { return .none }
        let render = ["png", "heic"].lazy.compactMap { bundle.url(forResource: profileID, withExtension: $0, subdirectory: folder) }.first
        return EarbudArtwork(model: bundle.url(forResource: profileID, withExtension: "usdz", subdirectory: folder), render: render)
    }

    /// What the user allows the card to show (Settings ▸ Connection Card ▸ Artwork).
    func restricted(to style: CardArtworkStyle) -> EarbudArtwork {
        switch style {
        case .automatic: self
        case .image: EarbudArtwork(render: render)
        case .symbol: .none
        }
    }
}

/// Settings ▸ Connection Card ▸ Artwork.
enum CardArtworkStyle: String, CaseIterable, Identifiable {
    case automatic, image, symbol

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "3D model when available"
        case .image: "Product image when available"
        case .symbol: "Symbol"
        }
    }
}

/// Settings ▸ Connection Card ▸ Hide after.
enum CardDuration: String, CaseIterable, Identifiable {
    case short, standard, long, untilClosed

    var id: Self { self }

    var title: String {
        switch self {
        case .short: "4 seconds"
        case .standard: "6 seconds"
        case .long: "10 seconds"
        case .untilClosed: "Until closed"
        }
    }

    /// nil: the card stays until it is closed or the earbuds disconnect.
    var duration: Duration? {
        switch self {
        case .short: .seconds(4)
        case .standard: .seconds(6)
        case .long: .seconds(10)
        case .untilClosed: nil
        }
    }
}
