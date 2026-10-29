import Foundation

/// Keeps audio preferences independent of menus and gameplay state.
final class MusicPreferences {
    private let defaults: UserDefaults
    private let key = "settings.musicEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var volume: Float {
        get {
            guard defaults.object(forKey: "settings.musicVolume") != nil else { return 0.32 }
            let saved = defaults.float(forKey: "settings.musicVolume")
            return saved.isFinite ? min(1, max(0, saved)) : 0.32
        }
        set {
            let value = newValue.isFinite ? min(1, max(0, newValue)) : 0.32
            defaults.set(value, forKey: "settings.musicVolume")
        }
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: key) }
    }
}
