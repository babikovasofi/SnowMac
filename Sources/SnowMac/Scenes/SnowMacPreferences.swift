import Foundation
import Combine

struct SnowMacSettings: Codable, Equatable {
    var snowfall = 0.25
    var depth = 40.0
    var wind = 0.0
    var snowOnSupports = true
    var autoPlow = false
    var clearsDock = false
    var plowAcrossDisplays: Bool?
    var displays = "all"
    var scene = SnowScene.current
    var lighting = SceneLighting.system
    var hasSeenGuide = false
}

final class SnowMacPreferences: ObservableObject {
    static let storageKey = "SnowMac.settings.v1"
    private let defaults: UserDefaults

    @Published var settings: SnowMacSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(SnowMacSettings.self, from: $0) } ?? SnowMacSettings()
    }
}
