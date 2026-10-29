import Foundation

enum ParkourMap: String, CaseIterable {
    case twilight, neon, jungle

    var title: String {
        switch self {
        case .twilight: return "Twilight Run"
        case .neon: return "Neon Rooftops"
        case .jungle: return "Jungle Rush"
        }
    }
    var number: String {
        switch self {
        case .twilight: return "01"
        case .neon: return "02"
        case .jungle: return "03"
        }
    }
    var length: CGFloat {
        switch self {
        case .twilight: return 16000
        case .neon: return 19000
        case .jungle: return 21000
        }
    }
    var description: String {
        switch self {
        case .twilight: return "Learn the rhythm · Long platforms"
        case .neon: return "Climb the skyline · Short rooftop chains"
        case .jungle: return "Brave the rain · Wild forest jumps"
        }
    }
}

/// Remembers map selection and each map's best progress independently.
final class MapProgress {
    private let defaults: UserDefaults
    private(set) var selected: ParkourMap

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selected = ParkourMap(rawValue: defaults.string(forKey: "maps.selected") ?? "") ?? .twilight
    }

    func select(_ map: ParkourMap) {
        selected = map
        defaults.set(map.rawValue, forKey: "maps.selected")
    }

    func best(for map: ParkourMap) -> Int {
        min(100, max(0, defaults.integer(forKey: "maps.best.\(map.rawValue)")))
    }

    func record(_ percent: Int, for map: ParkourMap) {
        defaults.set(max(best(for: map), min(100, max(0, percent))), forKey: "maps.best.\(map.rawValue)")
    }
}
