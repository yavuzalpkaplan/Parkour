import AVFoundation

/// Plays pre-rendered loops; no synthesis or per-frame audio work runs in the game.
final class MusicController: NSObject {
    enum Track: String {
        case twilight, neon, jungle

        init(map: ParkourMap) {
            switch map {
            case .twilight: self = .twilight
            case .neon: self = .neon
            case .jungle: self = .jungle
            }
        }
    }

    static let shared = MusicController()
    private let preferences = MusicPreferences()
    private var requestedTrack: Track?
    private var loadedTrack: Track?
    private var player: AVAudioPlayer?
    private var suspended = false
    private var interrupted = false
    var isEnabled: Bool { preferences.isEnabled }
    private(set) var volume: Float = 0.32

    private override init() {
        super.init()
        volume = preferences.volume
        NotificationCenter.default.addObserver(self, selector: #selector(audioDeactivated(_:)),
                                              name: AVAudioSession.didBecomeInactiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumptionRecommended(_:)),
                                              name: AVAudioSession.resumptionRecommendationNotification, object: nil)
    }

    func play(_ track: Track, restart: Bool = false) {
        requestedTrack = track
        guard isEnabled, !suspended, !interrupted else { return }
        if loadedTrack == track, let player {
            if restart { player.currentTime = 0 }
            if !player.isPlaying || restart {
                activateSession()
                player.volume = 0
                player.play()
                player.setVolume(volume, fadeDuration: 0.25)
            }
            return
        }
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a", subdirectory: "Audio")
                ?? Bundle.main.url(forResource: track.rawValue, withExtension: "m4a") else {
            NSLog("Missing music track: %@", track.rawValue)
            return
        }
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1
            next.volume = 0
            next.prepareToPlay()
            activateSession()
            // Stop the old track before starting another; never layer map music.
            player?.stop()
            player = next
            loadedTrack = track
            next.play()
            next.setVolume(volume, fadeDuration: 0.4)
        } catch {
            NSLog("Unable to play music: %@", error.localizedDescription)
        }
    }

    func setVolume(_ value: Float, persist: Bool = true) {
        volume = value.isFinite ? min(1, max(0, value)) : 0.32
        if isEnabled, !suspended, !interrupted {
            player?.setVolume(volume, fadeDuration: 0.03)
        }
        // Save once when dragging finishes, rather than writing on every touch update.
        if persist { preferences.volume = volume }
    }

    func toggle() {
        preferences.isEnabled.toggle()
        if isEnabled {
            if let requestedTrack { play(requestedTrack) }
        } else {
            pauseAllPlayers()
            deactivateSession()
        }
    }

    func suspend() {
        suspended = true
        preferences.volume = volume
        pauseAllPlayers()
        deactivateSession()
    }

    func resume() {
        suspended = false
        if let requestedTrack { play(requestedTrack) }
    }

    private func pauseAllPlayers() {
        player?.pause()
    }

    private func activateSession() {
        do {
            // Respect the silent switch and allow the user's other audio to continue.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("Unable to activate audio: %@", error.localizedDescription)
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private func audioDeactivated(_ notification: Notification) {
        guard let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext,
              context.source == .system else { return }
        Task { @MainActor [weak self] in
            self?.interrupted = true
            self?.pauseAllPlayers()
        }
    }

    @objc private func resumptionRecommended(_ notification: Notification) {
        guard let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext,
              context.recommendation == .shouldResume else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.interrupted = false
            if !self.suspended, let track = self.requestedTrack { self.play(track) }
        }
    }
}
