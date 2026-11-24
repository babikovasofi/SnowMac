import Foundation

enum SnowScene: String, Codable, CaseIterable, Identifiable {
    case current
    case village
    case cabins
    case square
    case bakery
    case station

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: "Current wallpaper"
        case .village: "Fir Tree Village"
        case .cabins: "Alpine Cabins"
        case .square: "Winter Square"
        case .bakery: "Corner Bakery"
        case .station: "Lakeside Station"
        }
    }

    func imageURL(lighting: SceneLighting, darkAppearance: Bool, bundle: Bundle = .main) -> URL? {
        guard self != .current else { return nil }
        let variant = lighting.isNight(darkAppearance: darkAppearance) ? "night" : "day"
        return bundle.url(forResource: "snowmac-\(rawValue)-\(variant)", withExtension: "jpg")
    }

    func previewURL(bundle: Bundle = .main) -> URL? {
        guard self != .current else { return nil }
        return bundle.url(forResource: "snowmac-\(rawValue)-preview", withExtension: "jpg")
    }
}

enum SceneLighting: String, Codable, CaseIterable, Identifiable {
    case system
    case day
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .day: "Day"
        case .night: "Night"
        }
    }

    func isNight(darkAppearance: Bool) -> Bool {
        switch self {
        case .system: darkAppearance
        case .day: false
        case .night: true
        }
    }
}
