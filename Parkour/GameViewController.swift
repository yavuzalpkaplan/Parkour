//
//  GameViewController.swift
//  Parkour
//
//  Created by Yavuzalp Kaplan on 29.10.2026.
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let view = self.view as? SKView else { return }

        // Create the scene in Swift instead of loading the scene file.
        let scene = GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        view.presentScene(scene)

        view.ignoresSiblingOrder = true
        view.showsFPS = false
        view.showsNodeCount = false
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
