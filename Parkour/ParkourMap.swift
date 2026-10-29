import Foundation

enum ParkourMap: String, CaseIterable {
    case twilight, neon

    var title: String { self == .twilight ? "Twilight Run" : "Neon Rooftops" }
    var number: String { self == .twilight ? "01" : "02" }
    var length: CGFloat { self == .twilight ? 16000 : 19000 }
    var description: String {
        self == .twilight ? "Learn the rhythm · Long platforms" : "Climb the skyline · Short rooftop chains"
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
