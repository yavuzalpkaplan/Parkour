import SpriteKit

class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum State { case menu, playing, lost, won }
    private var state: State = .menu
    private let scenery = SKNode()
    private let course = SKNode()
    private let hud = SKNode()
    private let overlay = SKNode()
    private let player = SKSpriteNode(color: .systemOrange, size: CGSize(width: 36, height: 36))
    private let progressFill = SKSpriteNode(color: .systemMint, size: .zero)
    private let progressLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var distance: CGFloat = 0
    private let finishDistance: CGFloat = 16000
    private var lastTime: TimeInterval = 0
    private var jumpRequestedAt: TimeInterval?
    private var isOnGround = true
    private var pendingCollision = false
    private var floorY: CGFloat { size.height * 0.22 }
    private var runnerX: CGFloat { min(120, size.width * 0.27) }
    private var safeTop: CGFloat { view?.safeAreaInsets.top ?? 0 }
    private var barWidth: CGFloat { max(100, size.width - 120) }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -12)
        physicsWorld.contactDelegate = self
        addChild(scenery)
        addChild(course)
        addChild(player)
        addChild(hud)
        addChild(overlay)
        scenery.zPosition = -10
        hud.zPosition = 20
        overlay.zPosition = 30
        player.zPosition = 5
        configurePlayer()
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard player.parent != nil else { return }
        // Restart at the menu when the screen orientation changes.
        rebuild()
    }

    private func configurePlayer() {
        player.physicsBody = SKPhysicsBody(rectangleOf: player.size)
        player.physicsBody?.allowsRotation = false
        player.physicsBody?.restitution = 0
        player.physicsBody?.linearDamping = 0
        player.physicsBody?.usesPreciseCollisionDetection = true
        player.physicsBody?.categoryBitMask = 1
        player.physicsBody?.collisionBitMask = 2
        player.physicsBody?.contactTestBitMask = 4
        let eye = SKSpriteNode(color: .white, size: CGSize(width: 7, height: 7))
        eye.position = CGPoint(x: 8, y: 5)
        player.addChild(eye)
    }

    private func rebuild() {
        distance = 0
        course.removeAllChildren()
        scenery.removeAllChildren()
        hud.removeAllChildren()
        buildBackground()
        buildCourse()
        buildHUD()
        resetPlayer()
        state = .menu
        showOverlay(title: "PARKOUR", subtitle: "01 / Twilight Run", button: "START")
        state = .menu
    }

    private func buildBackground() {
        backgroundColor = SKColor(red: 0.09, green: 0.12, blue: 0.24, alpha: 1)
        let moon = SKShapeNode(circleOfRadius: 34)
        moon.fillColor = SKColor(red: 1, green: 0.84, blue: 0.65, alpha: 1)
        moon.strokeColor = .clear
        moon.position = CGPoint(x: size.width * 0.78, y: size.height * 0.72)
        scenery.addChild(moon)

        // Each skyline moves at a different speed to create depth.
        for layer in 0..<2 {
            let spacing: CGFloat = layer == 0 ? 110 : 75
            for index in 0..<Int(size.width / spacing) + 3 {
                let height = CGFloat(70 + (index * 47 + layer * 29) % 130)
                let building = SKSpriteNode(color: layer == 0
                    ? SKColor(red: 0.17, green: 0.22, blue: 0.36, alpha: 1)
                    : SKColor(red: 0.12, green: 0.17, blue: 0.28, alpha: 1),
                    size: CGSize(width: spacing - 8, height: height))
                building.anchorPoint = CGPoint(x: 0, y: 0)
                building.position = CGPoint(x: CGFloat(index) * spacing, y: floorY)
                building.name = "layer\(layer)"
                building.userData = ["originX": CGFloat(index) * spacing,
                                     "span": CGFloat(Int(size.width / spacing) + 3) * spacing]
                if layer == 1 {
                    let light = SKSpriteNode(color: SKColor.systemYellow.withAlphaComponent(0.55), size: CGSize(width: 5, height: 12))
                    light.position = CGPoint(x: 16, y: height - 25)
                    building.addChild(light)
                }
                scenery.addChild(building)
            }
        }
    }

    private func buildCourse() {
        let ground = SKSpriteNode(color: SKColor(red: 0.13, green: 0.24, blue: 0.29, alpha: 1), size: CGSize(width: size.width, height: floorY))
        ground.anchorPoint = .zero
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.size, center: CGPoint(x: size.width / 2, y: floorY / 2))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = 2
        course.addChild(ground)
        let edge = SKSpriteNode(color: .systemMint, size: CGSize(width: size.width, height: 3))
        edge.position = CGPoint(x: size.width / 2, y: floorY)
        course.addChild(edge)

        // Build a repeatable course with harder obstacles in later sections.
        var worldX: CGFloat = 800
        var index = 0
        while worldX < finishDistance - 500 {
            let difficulty = worldX / finishDistance
            let width: CGFloat = index % 3 == 0 ? 56 : 32
            let height: CGFloat = 42 + difficulty * 42
            let obstacle = SKSpriteNode(color: .systemPink, size: CGSize(width: width, height: height))
            obstacle.name = "obstacle"
            obstacle.userData = ["worldX": worldX]
            obstacle.position = CGPoint(x: runnerX + worldX, y: floorY + height / 2)
            obstacle.physicsBody = SKPhysicsBody(rectangleOf: obstacle.size)
            obstacle.physicsBody?.isDynamic = false
            obstacle.physicsBody?.categoryBitMask = 4
            obstacle.physicsBody?.collisionBitMask = 0
            course.addChild(obstacle)
            // Spacing leaves enough time to land and jump again at maximum speed.
            worldX += 520 - difficulty * 90 + CGFloat(index % 3) * 35
            index += 1
        }
        for index in 0...Int(finishDistance / 100) {
            let mark = SKSpriteNode(color: .systemMint.withAlphaComponent(0.2), size: CGSize(width: 25, height: 3))
            mark.name = "mark"
            mark.userData = ["worldX": CGFloat(index) * 100]
            mark.position.y = floorY - 24
            course.addChild(mark)
        }
    }

    private func buildHUD() {
        let track = SKSpriteNode(color: .white.withAlphaComponent(0.15), size: CGSize(width: barWidth, height: 6))
        track.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.position = CGPoint(x: 28, y: size.height - safeTop - 40)
        hud.addChild(track)
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressFill.position = track.position
        hud.addChild(progressFill)
        progressLabel.fontSize = 13
        progressLabel.horizontalAlignmentMode = .right
        progressLabel.position = CGPoint(x: size.width - 24, y: track.position.y - 5)
        hud.addChild(progressLabel)
        updateProgress()
    }

    private func resetPlayer() {
        player.position = CGPoint(x: runnerX, y: floorY + player.size.height / 2)
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = false
        pendingCollision = false
        jumpRequestedAt = nil
        isOnGround = true
    }

    private func showOverlay(title: String, subtitle: String, button: String) {
        overlay.removeAllChildren()
        let shade = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: size)
        shade.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(shade)
        let centerY = size.height * 0.55
        addLabel(title, size: 38, y: centerY + 65, to: overlay)
        addLabel(subtitle, size: 16, y: centerY + 28, to: overlay)
        let start = SKShapeNode(rectOf: CGSize(width: 210, height: 54), cornerRadius: 16)
        start.name = "start"
        start.fillColor = .systemMint
        start.strokeColor = .clear
        start.position = CGPoint(x: size.width / 2, y: centerY - 28)
        overlay.addChild(start)
        let text = addLabel(button, size: 19, y: -7, to: start)
        text.position.x = 0
        text.fontColor = .black
        text.name = "start"
        if state == .menu {
            addLabel("MAP · Yakında     SKINS · Yakında", size: 13, y: centerY - 90, to: overlay)
        } else {
            let menu = addLabel("MENÜYE DÖN", size: 15, y: centerY - 90, to: overlay)
            menu.name = "menu"
        }
    }

    @discardableResult
    private func addLabel(_ text: String, size fontSize: CGFloat, y: CGFloat, to parent: SKNode) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = fontSize
        label.position = CGPoint(x: size.width / 2, y: y)
        parent.addChild(label)
        return label
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if state != .playing {
            let names = nodes(at: touch.location(in: self)).compactMap(\.name)
            if names.contains("menu") {
                state = .menu
                rebuild()
            } else if names.contains("start") {
                distance = 0
                resetPlayer()
                updateWorld()
                updateProgress()
                overlay.removeAllChildren()
                state = .playing
                player.physicsBody?.isDynamic = true
            }
            return
        }
        jumpRequestedAt = ProcessInfo.processInfo.systemUptime
        tryJump()
    }

    private func tryJump() {
        guard state == .playing, !pendingCollision, let requested = jumpRequestedAt else { return }
        guard ProcessInfo.processInfo.systemUptime - requested <= 0.18 else {
            jumpRequestedAt = nil
            return
        }
        guard isOnGround else { return }
        jumpRequestedAt = nil
        isOnGround = false
        player.physicsBody?.velocity = CGVector(dx: 0, dy: 720)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if state == .playing && (contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask) == 5 {
            pendingCollision = true
        }
    }

    override func didSimulatePhysics() {
        guard state == .playing, !pendingCollision, let body = player.physicsBody else { return }
        isOnGround = abs(player.position.y - player.size.height / 2 - floorY) <= 2 && abs(body.velocity.dy) < 5
        tryJump()
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 30)
        lastTime = currentTime
        guard state == .playing else { return }
        if pendingCollision {
            endRound(won: false)
            return
        }
        distance = min(finishDistance, distance + CGFloat(delta) * (200 + 100 * distance / finishDistance))
        updateWorld()
        updateProgress()
        if distance >= finishDistance { endRound(won: true) }
    }

    private func updateWorld() {
        for node in course.children where node.name == "obstacle" || node.name == "mark" {
            guard let worldX = node.userData?["worldX"] as? CGFloat else { continue }
            node.position.x = runnerX + worldX - distance
        }
        for node in scenery.children {
            guard let origin = node.userData?["originX"] as? CGFloat,
                  let span = node.userData?["span"] as? CGFloat else { continue }
            let factor: CGFloat = node.name == "layer0" ? 0.15 : 0.35
            let offset = (origin - distance * factor).truncatingRemainder(dividingBy: span)
            node.position.x = (offset + span).truncatingRemainder(dividingBy: span)
            if node.position.x > size.width + 110 { node.position.x -= span }
        }
    }

    private func updateProgress() {
        let progress = distance / finishDistance
        progressFill.size = CGSize(width: barWidth * progress, height: 6)
        progressLabel.text = "\(Int(progress * 100))%"
    }

    private func endRound(won: Bool) {
        state = won ? .won : .lost
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = false
        showOverlay(title: won ? "TAMAMLANDI!" : "TEKRAR DENE", subtitle: "Twilight Run · %\(Int(distance / finishDistance * 100))", button: "YENİDEN BAŞLA")
    }
}
