import Foundation

/// Stores earned coins independently of the current run.
final class CoinWallet {
    private let defaults: UserDefaults
    private let balanceKey = "coinWallet.balance"
    private(set) var balance: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        balance = max(0, defaults.integer(forKey: balanceKey))
    }

    @discardableResult
    func spend(_ amount: Int) -> Bool {
        guard amount > 0, balance >= amount else { return false }
        balance -= amount
        defaults.set(balance, forKey: balanceKey)
        return true
    }

    func earn(_ amount: Int) {
        guard amount > 0 else { return }
        balance += amount
        defaults.set(balance, forKey: balanceKey)
    }
}
