import Foundation

enum AchievementID: String, CaseIterable {
    case coinCollector, coinRun, newLook, twilightRunner, neonMaster

    var title: String {
        switch self {
        case .coinCollector: return "Coin Collector"
        case .coinRun: return "Coin Run"
        case .newLook: return "New Look"
        case .twilightRunner: return "Twilight Runner"
        case .neonMaster: return "Neon Master"
        }
    }

    var targets: [Int] {
        switch self {
        case .coinCollector: return [100, 1000, 10000]
        case .coinRun: return [30, 60, 100]
        case .newLook: return [1, 2, 4]
        case .twilightRunner, .neonMaster: return [1]
        }
    }

    func detail(target: Int) -> String {
        let amount = target.formatted(.number.locale(Locale(identifier: "en_US")))
        switch self {
        case .coinCollector: return "Earn \(amount) coins"
        case .coinRun: return "Collect \(amount) coins in one run"
        case .newLook: return "Buy \(amount) \(target == 1 ? "skin" : "skins")"
        case .twilightRunner: return "Complete Twilight Run"
        case .neonMaster: return "Complete Neon Rooftops"
        }
    }
}

struct AchievementUnlock: Equatable {
    let id: AchievementID
    let stage: Int
    var title: String {
        id.targets.count == 1 ? id.title : "\(id.title) · \(["I", "II", "III"][stage - 1])"
    }
}

/// Tracks milestones when gameplay events occur, never on every rendered frame.
final class AchievementStore {
    private let defaults: UserDefaults
    private var unlocked: Set<String>
    private(set) var bestRunCoins: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unlocked = Set(defaults.stringArray(forKey: "achievements.unlocked") ?? [])
        bestRunCoins = max(0, defaults.integer(forKey: "achievements.bestRunCoins"))
        // Reconcile legacy Coin Run stars with the current thresholds and saved best run.
        let savedUnlocks = unlocked
        unlocked = unlocked.filter { !$0.hasPrefix("coinRun.") }
        for (index, target) in AchievementID.coinRun.targets.enumerated() where bestRunCoins >= target {
            unlocked.insert("coinRun.\(index + 1)")
        }
        if unlocked != savedUnlocks {
            defaults.set(Array(unlocked), forKey: "achievements.unlocked")
        }
    }

    func value(for id: AchievementID, wallet: CoinWallet, skins: SkinStore, maps: MapProgress) -> Int {
        switch id {
        case .coinCollector: return wallet.lifetimeEarned
        case .coinRun: return bestRunCoins
        case .newLook: return RunnerSkin.allCases.filter { $0.price > 0 && skins.owns($0) }.count
        case .twilightRunner: return maps.best(for: .twilight) == 100 ? 1 : 0
        case .neonMaster: return maps.best(for: .neon) == 100 ? 1 : 0
        }
    }

    func completedStages(for id: AchievementID) -> Int {
        id.targets.indices.filter { unlocked.contains(key(id, stage: $0 + 1)) }.count
    }

    @discardableResult
    func refresh(wallet: CoinWallet, skins: SkinStore, maps: MapProgress, runCoins: Int = 0) -> [AchievementUnlock] {
        if runCoins > bestRunCoins {
            bestRunCoins = runCoins
            defaults.set(bestRunCoins, forKey: "achievements.bestRunCoins")
        }
        var newlyUnlocked: [AchievementUnlock] = []
        for id in AchievementID.allCases {
            let progress = value(for: id, wallet: wallet, skins: skins, maps: maps)
            for (index, target) in id.targets.enumerated() where progress >= target {
                if unlocked.insert(key(id, stage: index + 1)).inserted {
                    newlyUnlocked.append(AchievementUnlock(id: id, stage: index + 1))
                }
            }
        }
        if !newlyUnlocked.isEmpty {
            defaults.set(Array(unlocked), forKey: "achievements.unlocked")
        }
        return newlyUnlocked
    }

    private func key(_ id: AchievementID, stage: Int) -> String { "\(id.rawValue).\(stage)" }
}
