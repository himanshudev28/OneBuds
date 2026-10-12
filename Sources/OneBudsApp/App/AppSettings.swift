import Foundation
import Observation
import OneBudsCore

/// User preferences, persisted locally in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let demoModels = DeviceRegistry.all.filter(\.allowsControlSession)

    private let defaults: UserDefaults

    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            appearance.apply()
        }
    }

    var visualStyle: VisualStyle {
        didSet { defaults.set(visualStyle.rawValue, forKey: "visualStyle") }
    }

    var showBatteryInMenuBar: Bool {
        didSet { defaults.set(showBatteryInMenuBar, forKey: "showBatteryInMenuBar") }
    }

    /// Show the floating connection card when earbuds connect.
    var showConnectionCard: Bool {
        didSet { defaults.set(showConnectionCard, forKey: "showConnectionCard") }
    }

    /// How long the connection card stays up on its own.
    var cardDuration: CardDuration {
        didSet { defaults.set(cardDuration.rawValue, forKey: "cardDuration") }
    }

    /// Which artwork the connection card may use (always within what is installed).
    var cardArtworkStyle: CardArtworkStyle {
        didSet { defaults.set(cardArtworkStyle.rawValue, forKey: "cardArtworkStyle") }
    }

    /// Gentle sway of a 3D model on the card. Reduce Motion always holds it still.
    var animateCardModel: Bool {
        didSet { defaults.set(animateCardModel, forKey: "animateCardModel") }
    }

    private(set) var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: "demoMode") }
    }

    /// Which model Demo mode simulates.
    private(set) var demoModelID: String {
        didSet { defaults.set(demoModelID, forKey: "demoModelID") }
    }

    var demoProfile: DeviceProfile {
        Self.demoModels.first { $0.id == demoModelID } ?? DeviceRegistry.onePlusBuds3
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        visualStyle = VisualStyle(rawValue: defaults.string(forKey: "visualStyle") ?? "") ?? .standard
        showBatteryInMenuBar = defaults.object(forKey: "showBatteryInMenuBar") as? Bool ?? true
        showConnectionCard = defaults.object(forKey: "showConnectionCard") as? Bool ?? true
        cardDuration = CardDuration(rawValue: defaults.string(forKey: "cardDuration") ?? "") ?? .standard
        cardArtworkStyle = CardArtworkStyle(rawValue: defaults.string(forKey: "cardArtworkStyle") ?? "") ?? .automatic
        animateCardModel = defaults.object(forKey: "animateCardModel") as? Bool ?? true
        demoMode = defaults.bool(forKey: "demoMode")
        demoModelID = defaults.string(forKey: "demoModelID") ?? DeviceRegistry.onePlusBuds3.id
    }

    func setDemoMode(_ value: Bool) { demoMode = value }
    func setDemoModel(_ id: String) { demoModelID = id }
}
