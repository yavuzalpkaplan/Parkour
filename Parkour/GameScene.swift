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
    private let wallet = CoinWallet()
    private let walletLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var coinNodes: [SKNode] = []
    private var movingHazards: [SKNode] = []
    private var textureCache: [String: SKTexture] = [:]
    private var displayedPercent = -1
    private var collectedCoins = 0
    private var totalCoins = 0
    private let progressLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private struct Platform {
        let start: CGFloat
        let end: CGFloat
        let elevation: CGFloat
    }
    private var platforms: [Platform] = []
    private var runTime: TimeInterval = 0
    private var distance: CGFloat = 0
    private let finishDistance: CGFloat = 16000
    private var lastTime: TimeInterval = 0
    // A stronger launch and gravity preserve height while shortening airtime.
    private let jumpSpeed: CGFloat = 880
    private let gravityStrength: CGFloat = 18
    private var jumpRequestedAt: TimeInterval?
    private var isOnGround = true
    private var pendingCollision = false
    private var hitPlatformWall = false
    private var floorY: CGFloat { size.height * 0.22 }
    private var runnerX: CGFloat { min(120, size.width * 0.27) }
    private var safeTop: CGFloat { view?.safeAreaInsets.top ?? 0 }
    private var barWidth: CGFloat { max(100, size.width - 120) }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -gravityStrength)
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
        player.physicsBody?.friction = 0
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
        platforms.removeAll()
        totalCoins = 0
        coinNodes.removeAll()
        movingHazards.removeAll()
        // Start with safe ground, then introduce gaps and raised landings.
        var start: CGFloat = -300
        var index = 0
        while start < finishDistance + 500 {
            let difficulty = max(0, start / finishDistance)
            var length: CGFloat = index == 0 ? 1500 : 850 - difficulty * 160
            // Keep the finish line on a wide, safe landing instead of inside a gap.
            if start + length >= finishDistance - 400 {
                length = finishDistance + 600 - start
            }
            let elevation: CGFloat = index < 2 ? 0 : [CGFloat(0), 45, 85, 30][index % 4]
            let platform = Platform(start: start, end: start + length, elevation: elevation)
            platforms.append(platform)
            addPlatform(platform)

            if index == 0 {
                addSpikes(at: 650, elevation: 0, count: 2)
            } else if start + length * 0.52 < finishDistance - 350 {
                // Keep hazards away from the landing and takeoff edges.
                let hazardX = start + length * 0.52
                if index >= 3 && index % 3 == 0 {
                    addMovingHazard(at: hazardX, elevation: elevation)
                } else {
                    addSpikes(at: hazardX, elevation: elevation, count: difficulty > 0.45 ? 3 : 2)
                }
            }
            // Offer a safe trail and an optional reward above the hazard.
            let safeStart = max(180, start + 130)
            for offset in 0..<3 {
                addCoin(at: safeStart + CGFloat(offset) * 48, y: floorY + elevation + 30)
            }
            let rewardX: CGFloat = index == 0 ? 674 : start + length * 0.52 + 20
            addCoin(at: rewardX, y: floorY + elevation + 150)
            let gap: CGFloat = index == 0 ? 85 : 95 + difficulty * 45
            start = platform.end + gap
            index += 1
        }
        buildFinish()
        // Assign world coordinates once; scrolling now changes only the parent transform.
        for node in course.children {
            if let worldX = node.userData?["worldX"] as? CGFloat {
                node.position.x = runnerX + worldX
            }
        }
        updateWorld()
    }

    private func buildFinish() {
        guard let platform = platforms.first(where: { $0.start <= finishDistance && $0.end >= finishDistance }) else { return }
        let finish = SKNode()
        finish.name = "finish"
        finish.userData = ["worldX": finishDistance]
        finish.position.y = floorY + platform.elevation
        finish.zPosition = 2
        course.addChild(finish)

        let pole = SKSpriteNode(color: .white, size: CGSize(width: 5, height: 160))
        pole.position = CGPoint(x: 0, y: 80)
        finish.addChild(pole)
        // A checkered flag makes the destination visible before the runner arrives.
        for row in 0..<4 {
            for column in 0..<6 {
                let tile = SKSpriteNode(color: (row + column).isMultiple(of: 2) ? .white : .black,
                                        size: CGSize(width: 11, height: 11))
                tile.position = CGPoint(x: 8 + CGFloat(column) * 11, y: 150 - CGFloat(row) * 11)
                finish.addChild(tile)
            }
        }
        let line = SKSpriteNode(color: .systemMint, size: CGSize(width: 10, height: 10))
        line.position.y = 3
        finish.addChild(line)
        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "FINISH"
        title.fontSize = 18
        title.fontColor = .systemMint
        title.position = CGPoint(x: 28, y: 178)
        finish.addChild(title)
    }

    private func addPlatform(_ platform: Platform) {
        let width = platform.end - platform.start
        let depth: CGFloat = floorY + platform.elevation + 180
        let node = SKSpriteNode(color: SKColor(red: 0.13, green: 0.24, blue: 0.29, alpha: 1), size: CGSize(width: width, height: depth))
        node.anchorPoint = CGPoint(x: 0, y: 1)
        node.name = "platform"
        node.userData = ["worldX": platform.start]
        node.position.y = floorY + platform.elevation
        // Match the entire visible platform, including its vertical walls.
        node.physicsBody = SKPhysicsBody(rectangleOf: node.size, center: CGPoint(x: width / 2, y: -depth / 2))
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = 2
        node.physicsBody?.friction = 0
        node.physicsBody?.restitution = 0
        course.addChild(node)
        let edge = SKSpriteNode(color: .systemMint, size: CGSize(width: width, height: 4))
        edge.anchorPoint = CGPoint(x: 0, y: 0.5)
        node.addChild(edge)
        for x in stride(from: CGFloat(25), to: width, by: 90) {
            let mark = SKSpriteNode(color: .systemMint.withAlphaComponent(0.2), size: CGSize(width: 25, height: 3))
            mark.position = CGPoint(x: x, y: -25)
            node.addChild(mark)
        }
    }

    private func addSpikes(at worldX: CGFloat, elevation: CGFloat, count: Int) {
        for index in 0..<count {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -12, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 38))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.closeSubpath()
            let shape = SKShapeNode(path: path)
            shape.fillColor = .systemPink
            shape.strokeColor = .white.withAlphaComponent(0.65)
            shape.lineWidth = 1.5
            let spike = rasterized(shape, key: "spike")
            spike.name = "obstacle"
            spike.userData = ["worldX": worldX + CGFloat(index) * 24]
            spike.position.y = floorY + elevation
            spike.physicsBody = SKPhysicsBody(polygonFrom: path)
            spike.physicsBody?.isDynamic = false
            spike.physicsBody?.categoryBitMask = 4
            spike.physicsBody?.collisionBitMask = 0
            course.addChild(spike)
        }
    }

    private func addMovingHazard(at worldX: CGFloat, elevation: CGFloat) {
        let path = CGMutablePath()
        for index in 0..<24 {
            let angle = CGFloat(index) * .pi / 12
            let radius: CGFloat = index.isMultiple(of: 2) ? 25 : 18
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = .systemPink
        shape.strokeColor = .white
        shape.lineWidth = 2
        let saw = rasterized(shape, key: "saw")
        saw.name = "movingHazard"
        saw.userData = ["worldX": worldX, "baseY": floorY + elevation + 38]
        saw.physicsBody = SKPhysicsBody(circleOfRadius: 22)
        saw.physicsBody?.isDynamic = false
        saw.physicsBody?.categoryBitMask = 4
        saw.physicsBody?.collisionBitMask = 0
        course.addChild(saw)
        movingHazards.append(saw)
    }

    private func addCoin(at worldX: CGFloat, y: CGFloat) {
        guard worldX > 0, worldX < finishDistance else { return }
        let shape = SKShapeNode(circleOfRadius: 10)
        shape.fillColor = .systemYellow
        shape.strokeColor = SKColor(red: 1, green: 0.88, blue: 0.45, alpha: 1)
        shape.lineWidth = 2
        let shine = SKSpriteNode(color: .white.withAlphaComponent(0.7), size: CGSize(width: 3, height: 9))
        shine.position.x = -3
        shape.addChild(shine)
        let coin = rasterized(shape, key: "coin")
        coin.name = "coin"
        coin.zPosition = 3
        coin.userData = ["worldX": worldX]
        coin.position.y = y
        course.addChild(coin)
        coinNodes.append(coin)
        totalCoins += 1
    }

    private func rasterized(_ shape: SKShapeNode, key: String) -> SKNode {
        let bounds = shape.calculateAccumulatedFrame().insetBy(dx: -2, dy: -2)
        if textureCache[key] == nil {
            textureCache[key] = view?.texture(from: shape, crop: bounds)
        }
        let node = SKNode()
        if let texture = textureCache[key] {
            let sprite = SKSpriteNode(texture: texture, size: bounds.size)
            sprite.position = CGPoint(x: bounds.midX, y: bounds.midY)
            node.addChild(sprite)
        } else {
            node.addChild(shape)
        }
        return node
    }

    private func resetCoins() {
        collectedCoins = 0
        for coin in coinNodes {
            coin.isHidden = false
        }
        hud.children.filter { $0.name == "pickupEffect" }.forEach { $0.removeFromParent() }
        updateCoinLabel()
    }

    private func updateCoinLabel() {
        walletLabel.text = "COINS  \(wallet.balance)"
    }

    private func collectNearbyCoins() {
        var earned = 0
        for coin in coinNodes where !coin.isHidden {
            let position = course.convert(coin.position, to: self)
            guard abs(position.x - player.position.x) < 32 else { continue }
            // Circle-versus-rectangle overlap avoids collecting from the corners of a large box.
            let closestX = max(player.frame.minX, min(position.x, player.frame.maxX))
            let closestY = max(player.frame.minY, min(position.y, player.frame.maxY))
            let dx = position.x - closestX
            let dy = position.y - closestY
            guard dx * dx + dy * dy <= 12 * 12 else { continue }
            coin.isHidden = true
            collectedCoins += 1
            earned += 1

            let effect = SKLabelNode(fontNamed: "AvenirNext-Bold")
            effect.name = "pickupEffect"
            effect.text = "+1"
            effect.fontSize = 18
            effect.fontColor = .systemYellow
            effect.position = position
            hud.addChild(effect)
            effect.run(.sequence([
                .group([.moveBy(x: 0, y: 35, duration: 0.4), .fadeOut(withDuration: 0.4)]),
                .removeFromParent()
            ]))
        }
        if earned > 0 {
            // Credit each pickup once; restarting never credits the run a second time.
            wallet.earn(earned)
            updateCoinLabel()
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
        walletLabel.fontSize = 14
        walletLabel.fontColor = .systemYellow
        walletLabel.horizontalAlignmentMode = .left
        walletLabel.position = CGPoint(x: 28, y: track.position.y - 32)
        hud.addChild(walletLabel)
        displayedPercent = -1
        updateCoinLabel()
        updateProgress()
    }

    private func resetPlayer() {
        player.position = CGPoint(x: runnerX, y: floorY + player.size.height / 2)
        runTime = 0
        lastTime = 0
        resetCoins()
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = false
        pendingCollision = false
        hitPlatformWall = false
        jumpRequestedAt = nil
        isOnGround = true
    }

    private func showOverlay(title: String, subtitle: String, button: String) {
        overlay.removeAllChildren()
        hud.isHidden = true
        let shade = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: size)
        shade.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(shade)
        let centerY = size.height * 0.55
        addLabel(title, size: 38, y: centerY + 65, to: overlay)
        addLabel(subtitle, size: 16, y: centerY + 28, to: overlay)
        let balance = addLabel("COINS  \(wallet.balance)", size: 15, y: size.height - safeTop - 40, to: overlay)
        balance.horizontalAlignmentMode = .left
        balance.position.x = 28
        balance.fontColor = .systemYellow
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
            addLabel("MAP · Soon     SKINS · Soon", size: 13, y: centerY - 90, to: overlay)
        } else {
            let menu = addLabel("MAIN MENU", size: 15, y: centerY - 90, to: overlay)
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
                hud.isHidden = false
                state = .playing
                player.physicsBody?.isDynamic = true
            }
            return
        }
        jumpRequestedAt = ProcessInfo.processInfo.systemUptime
        tryJump()
    }

    private func tryJump() {
        guard state == .playing, !pendingCollision, !hitPlatformWall, let requested = jumpRequestedAt else { return }
        guard ProcessInfo.processInfo.systemUptime - requested <= 0.18 else {
            jumpRequestedAt = nil
            return
        }
        guard isOnGround else { return }
        jumpRequestedAt = nil
        isOnGround = false
        player.physicsBody?.velocity = CGVector(dx: 0, dy: jumpSpeed)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if state == .playing && (contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask) == 5 {
            pendingCollision = true
        }
    }

    override func didSimulatePhysics() {
        guard state == .playing, !pendingCollision, let body = player.physicsBody else { return }
        // Let wall collisions resolve without teleporting the player into the platform.
        if !hitPlatformWall { player.position.x = runnerX }
        body.velocity.dx = 0
        let feetY = player.position.y - player.size.height / 2
        isOnGround = abs(body.velocity.dy) < 8 && platforms.contains { platform in
            distance + 12 >= platform.start && distance - 12 <= platform.end
                && abs(feetY - floorY - platform.elevation) <= 3
        }
        if !hitPlatformWall { collectNearbyCoins() }
        tryJump()
    }

    override func update(_ currentTime: TimeInterval) {
        // Preserve ordinary frame delays; discard time spent suspended in the background.
        let elapsed = lastTime == 0 ? 0 : max(0, currentTime - lastTime)
        let delta = elapsed > 0.25 ? 0 : elapsed
        lastTime = currentTime
        guard state == .playing else { return }
        if pendingCollision || player.position.y < -60 {
            endRound(won: false)
            return
        }
        runTime += delta
        if !hitPlatformWall {
            let nextDistance = min(finishDistance + player.size.width / 2, distance + CGFloat(delta) * (260 + 70 * distance / finishDistance))
            let halfWidth = player.size.width / 2
            let feetY = player.position.y - player.size.height / 2
            // Stop the world at the wall so it cannot scroll through a falling player.
            if let wall = platforms.first(where: {
                $0.start > distance + halfWidth - 1
                    && $0.start <= nextDistance + halfWidth
                    && feetY < floorY + $0.elevation - 2
            }) {
                distance = wall.start - halfWidth
                hitPlatformWall = true
                isOnGround = false
                jumpRequestedAt = nil
            } else {
                distance = nextDistance
            }
        }
        updateWorld()
        updateProgress()
        // Complete the run only after the entire runner has crossed the flag.
        if distance >= finishDistance + player.size.width / 2 { endRound(won: true) }
    }

    private func updateWorld() {
        course.position.x = -distance
        for node in movingHazards {
            if let baseY = node.userData?["baseY"] as? CGFloat {
                node.position.y = baseY + 24 * (1 + sin(CGFloat(runTime) * 2.5))
                node.zRotation = CGFloat(runTime) * 3
            }
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
        let progress = min(1, distance / finishDistance)
        progressFill.size = CGSize(width: barWidth * progress, height: 6)
        let percent = Int(progress * 100)
        if percent != displayedPercent {
            displayedPercent = percent
            progressLabel.text = "\(percent)%"
        }
    }

    private func endRound(won: Bool) {
        state = won ? .won : .lost
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = false
        showOverlay(title: won ? "COMPLETED!" : "TRY AGAIN", subtitle: "\(Int(min(1, distance / finishDistance) * 100))% · COINS \(collectedCoins)", button: "RESTART")
    }
}
