import Foundation

enum RunnerSkin: String, CaseIterable {
    case orange, mint, blue, violet, rose

    var title: String { rawValue.capitalized }
    var price: Int {
        switch self {
        case .orange: return 0
        case .mint, .blue, .violet, .rose: return 1000
        }
    }
}

/// Saves ownership and selection separately from each run.
final class SkinStore {
    private let defaults: UserDefaults
    private(set) var owned: Set<String>
    private(set) var selected: RunnerSkin

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        owned = Set(defaults.stringArray(forKey: "skins.owned") ?? [])
        owned.insert(RunnerSkin.orange.rawValue)
        let saved = RunnerSkin(rawValue: defaults.string(forKey: "skins.selected") ?? "") ?? .orange
        selected = owned.contains(saved.rawValue) ? saved : .orange
    }

    func owns(_ skin: RunnerSkin) -> Bool { owned.contains(skin.rawValue) }

    @discardableResult
    func selectOrBuy(_ skin: RunnerSkin, wallet: CoinWallet) -> Bool {
        if !owns(skin) {
            guard wallet.spend(skin.price) else { return false }
            owned.insert(skin.rawValue)
            defaults.set(Array(owned), forKey: "skins.owned")
        }
        selected = skin
        defaults.set(skin.rawValue, forKey: "skins.selected")
        return true
    }
}
