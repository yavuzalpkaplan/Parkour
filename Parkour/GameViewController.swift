//
//  GameViewController.swift
//  Parkour
//
//  Created by Yavuzalp Kaplan on 29.10.2026.
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    private var hasAppeared = false

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let gameView = view as? SKView else { return }
        gameView.backgroundColor = UIColor(red: 0.09, green: 0.12, blue: 0.24, alpha: 1)
        gameView.preferredFramesPerSecond = 60
        gameView.shouldCullNonVisibleNodes = true
        gameView.ignoresSiblingOrder = true
        gameView.showsFPS = false
        gameView.showsNodeCount = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        resumeGameIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Retry if the initial appearance happened before the view had a usable size.
        if hasAppeared, (view as? SKView)?.scene == nil {
            resumeGameIfNeeded()
        }
    }

    func resumeGameIfNeeded() {
        // Build textures only after the view is attached to an active, laid-out window.
        guard isViewLoaded, let gameView = view as? SKView,
              gameView.window?.windowScene?.activationState == .foregroundActive,
              gameView.bounds.width > 0, gameView.bounds.height > 0 else { return }
        gameView.isPaused = false
        MusicController.shared.resume()
        if let scene = gameView.scene as? GameScene {
            scene.resumeAfterInterruption()
        } else if gameView.scene == nil {
            let scene = GameScene(size: gameView.bounds.size)
            scene.scaleMode = .resizeFill
            gameView.presentScene(scene)
        }
    }

    func pauseGame() {
        guard isViewLoaded, let gameView = view as? SKView else { return }
        gameView.isPaused = true
        MusicController.shared.suspend()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
