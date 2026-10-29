import SpriteKit
import UIKit

class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum State { case menu, maps, skins, achievements, playing, lost, won }
    private var state: State = .menu
    private let scenery = SKNode()
    private let course = SKNode()
    private let hud = SKNode()
    private let overlay = SKNode()
    private let player = SKSpriteNode(color: .systemOrange, size: CGSize(width: 36, height: 36))
    private let progressFill = SKSpriteNode(color: .systemMint, size: .zero)
    private let wallet = CoinWallet()
    private let skins = SkinStore()
    private let achievements = AchievementStore()
    private let notifications = SKNode()
    private var achievementQueue: [AchievementUnlock] = []
    private var showingAchievement = false
    private var pendingSkinPurchase: RunnerSkin?
    private let walletLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var coinNodes: [SKNode] = []
    private var movingHazards: [SKNode] = []
    private struct CourseObject {
        let node: SKNode
        let body: SKPhysicsBody?
        let minX: CGFloat
        let maxX: CGFloat
    }
    private var courseObjects: [CourseObject] = []
    private var nearbyCoins: [SKNode] = []
    private var lastActivationDistance: CGFloat = -.infinity
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
    private let mapProgress = MapProgress()
    private var currentMap: ParkourMap { mapProgress.selected }
    private var finishDistance: CGFloat { currentMap.length }
    private var themeColor: SKColor { currentMap == .jungle ? .systemGreen : currentMap == .neon ? .cyan : .systemMint }
    private var lastTime: TimeInterval = 0
    // A stronger launch and gravity preserve height while shortening airtime.
    private let jumpSpeed: CGFloat = 880
    private let gravityStrength: CGFloat = 18
    private var jumpRequestedAt: TimeInterval?
    private var isOnGround = true
    private var pendingCollision = false
    private var hitPlatformWall = false
    private var floorY: CGFloat { size.height * (currentMap == .neon ? 0.34 : 0.22) }
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
        addChild(notifications)
        notifications.zPosition = 200
        // Reconcile previously saved purchases and completions without a burst of old popups.
        achievements.refresh(wallet: wallet, skins: skins, maps: mapProgress)
        scenery.zPosition = -10
        hud.zPosition = 20
        overlay.zPosition = 30
        player.zPosition = 5
        configurePlayer()
        rebuild()
    }

    func resumeAfterInterruption() {
        // Do not apply background time or stale taps to the next gameplay frame.
        lastTime = 0
        jumpRequestedAt = nil
        isPaused = false
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard player.parent != nil else { return }
        // Restart at the menu when the screen orientation changes.
        rebuild()
    }

    private func configurePlayer() {
        player.color = skinColor(skins.selected)
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
        pendingSkinPurchase = nil
        course.removeAllChildren()
        courseObjects.removeAll()
        nearbyCoins.removeAll()
        // Release map-specific facades when switching maps or rebuilding for rotation.
        textureCache = textureCache.filter { ["coin", "spike", "saw"].contains($0.key) }
        scenery.removeAllChildren()
        hud.removeAllChildren()
        buildBackground()
        buildCourse()
        buildHUD()
        resetPlayer()
        state = .menu
        showOverlay(title: "THE CUBE", subtitle: "\(currentMap.number) / \(currentMap.title)", button: "START")
        state = .menu
    }

    private func buildBackground() {
        if currentMap == .jungle {
            buildJungleBackground()
            return
        }
        let neon = currentMap == .neon
        backgroundColor = neon ? SKColor(red: 0.09, green: 0.04, blue: 0.19, alpha: 1)
            : SKColor(red: 0.09, green: 0.12, blue: 0.24, alpha: 1)
        let moon = SKShapeNode(circleOfRadius: 34)
        moon.fillColor = neon ? .systemPink : SKColor(red: 1, green: 0.84, blue: 0.65, alpha: 1)
        moon.strokeColor = .clear
        moon.position = CGPoint(x: size.width * 0.78, y: size.height * 0.72)
        scenery.addChild(moon)
        if neon {
            // Distant stars stay above the low skyline, emphasizing the rooftop height.
            let stars = CGMutablePath()
            for index in 0..<35 {
                let x = CGFloat((index * 79 + 23) % max(1, Int(size.width)))
                let y = size.height * 0.58 + CGFloat((index * 37) % max(1, Int(size.height * 0.3)))
                stars.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
            }
            let sky = SKShapeNode(path: stars)
            sky.fillColor = .white.withAlphaComponent(0.4)
            sky.strokeColor = .clear
            scenery.addChild(rasterized(sky, key: "stars-\(size.width)-\(size.height)"))
        }

        // Each skyline moves at a different speed to create depth.
        for layer in 0..<2 {
            let spacing: CGFloat = layer == 0 ? 110 : 75
            for index in 0..<Int(size.width / spacing) + 3 {
                let height = CGFloat(70 + (index * 47 + layer * 29) % 130) + (neon ? 100 : 0)
                let building = SKSpriteNode(color: layer == 0
                    ? SKColor(red: 0.17, green: 0.22, blue: 0.36, alpha: 1)
                    : SKColor(red: 0.12, green: 0.17, blue: 0.28, alpha: 1),
                    size: CGSize(width: spacing - 8, height: height))
                if neon {
                    building.color = layer == 0 ? SKColor(red: 0.22, green: 0.10, blue: 0.35, alpha: 1)
                        : SKColor(red: 0.12, green: 0.07, blue: 0.24, alpha: 1)
                    let neonEdge = SKSpriteNode(color: layer == 0 ? .systemPink : .cyan,
                                               size: CGSize(width: spacing - 8, height: 2))
                    neonEdge.position = CGPoint(x: (spacing - 8) / 2, y: height)
                    building.addChild(neonEdge)
                }
                building.anchorPoint = CGPoint(x: 0, y: 0)
                building.position = CGPoint(x: CGFloat(index) * spacing, y: neon ? -70 : floorY)
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

    private func buildJungleBackground() {
        backgroundColor = SKColor(red: 0.035, green: 0.12, blue: 0.13, alpha: 1)
        let tileWidth: CGFloat = 240
        let tileHeight = max(440, size.height * 0.9)
        let count = Int(ceil(size.width / tileWidth)) + 2
        for layer in 0..<2 {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let texture = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: tileWidth, height: tileHeight), format: format).image { context in
                let g = context.cgContext
                let trunk = layer == 0 ? UIColor(red: 0.07, green: 0.23, blue: 0.23, alpha: 1)
                    : UIColor(red: 0.04, green: 0.16, blue: 0.13, alpha: 1)
                let leaves = layer == 0 ? UIColor(red: 0.08, green: 0.29, blue: 0.26, alpha: 1)
                    : UIColor(red: 0.05, green: 0.23, blue: 0.15, alpha: 1)
                // Repeat edge trees inside the texture so adjacent tiles join seamlessly.
                for index in -1..<4 {
                    let patternIndex = (index + 3) % 3
                    let x = CGFloat(index) * 80 + (layer == 0 ? 8 : 35)
                    let crownY = CGFloat(35 + patternIndex * 47)
                    g.setFillColor(trunk.cgColor)
                    g.fill(CGRect(x: x + 22, y: crownY, width: 17 + CGFloat(patternIndex * 3), height: tileHeight))
                    g.setStrokeColor(trunk.cgColor)
                    g.setLineWidth(9)
                    g.move(to: CGPoint(x: x + 30, y: crownY + 210))
                    g.addLine(to: CGPoint(x: x - 15, y: crownY + 155))
                    g.move(to: CGPoint(x: x + 30, y: crownY + 140))
                    g.addLine(to: CGPoint(x: x + 72, y: crownY + 100))
                    g.strokePath()
                    g.setFillColor(leaves.cgColor)
                    for crown in 0..<3 {
                        g.fillEllipse(in: CGRect(x: x - 40 + CGFloat(crown) * 28,
                                                 y: crownY + CGFloat(crown % 2) * 30, width: 115, height: 100))
                    }
                    // Thin hanging vines add a forest silhouette without extra scene nodes.
                    g.setStrokeColor(leaves.cgColor)
                    g.setLineWidth(2)
                    g.move(to: CGPoint(x: x + 5, y: crownY + 70))
                    g.addQuadCurve(to: CGPoint(x: x + 2, y: crownY + 255), control: CGPoint(x: x - 22, y: crownY + 180))
                    g.strokePath()
                }
            })
            for index in 0..<count {
                let trees = SKSpriteNode(texture: texture, size: CGSize(width: tileWidth, height: tileHeight))
                trees.anchorPoint = .zero
                trees.position = CGPoint(x: CGFloat(index) * tileWidth, y: -40)
                trees.name = "layer\(layer)"
                trees.userData = ["originX": CGFloat(index) * tileWidth, "span": CGFloat(count) * tileWidth]
                scenery.addChild(trees)
            }
        }
        // A small, fixed particle budget keeps rain behind gameplay and away from the HUD.
        let rainFormat = UIGraphicsImageRendererFormat()
        rainFormat.scale = 1
        let drop = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 16), format: rainFormat).image { context in
            UIColor(red: 0.62, green: 0.84, blue: 0.90, alpha: 0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 16))
        }
        let rain = SKEmitterNode()
        rain.particleTexture = SKTexture(image: drop)
        rain.particleBirthRate = 65
        rain.particleLifetime = 2.2
        rain.particleLifetimeRange = 0.3
        rain.particlePositionRange = CGVector(dx: size.width + 160, dy: 0)
        rain.position = CGPoint(x: size.width / 2 + 50, y: size.height + 20)
        rain.emissionAngle = -.pi / 2 - 0.15
        rain.particleSpeed = 500
        rain.particleSpeedRange = 80
        rain.particleRotation = -0.15
        rain.particleAlpha = 0.45
        rain.particleAlphaSpeed = -0.08
        rain.particleScale = 0.7
        rain.particleScaleRange = 0.3
        rain.particleColorBlendFactor = 0
        rain.zPosition = 5
        scenery.addChild(rain)
        rain.advanceSimulationTime(1)
    }

    private func decorateJunglePlatform(_ node: SKSpriteNode, width: CGFloat, depth: CGFloat) {
        let key = "earth-\(Int(width))-\(Int(depth))"
        if textureCache[key] == nil {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: depth), format: format).image { context in
                let g = context.cgContext
                g.setFillColor(UIColor(red: 0.16, green: 0.13, blue: 0.09, alpha: 1).cgColor)
                g.fill(CGRect(x: 0, y: 0, width: width, height: depth))
                g.setFillColor(UIColor(red: 0.16, green: 0.37, blue: 0.12, alpha: 1).cgColor)
                g.fill(CGRect(x: 0, y: 0, width: width, height: 17))
                g.setStrokeColor(UIColor(red: 0.24, green: 0.21, blue: 0.12, alpha: 1).cgColor)
                g.setLineWidth(3)
                for x in stride(from: CGFloat(20), to: width, by: 65) {
                    g.move(to: CGPoint(x: x, y: 16))
                    g.addLine(to: CGPoint(x: x + 12, y: 60))
                    g.addLine(to: CGPoint(x: x - 6, y: 100))
                    g.strokePath()
                    g.setFillColor(UIColor(red: 0.24, green: 0.25, blue: 0.20, alpha: 1).cgColor)
                    g.fillEllipse(in: CGRect(x: x + 10, y: 130, width: 25, height: 12))
                }
            }
            textureCache[key] = SKTexture(image: image)
        }
        node.texture = textureCache[key]
        node.colorBlendFactor = 0
        node.blendMode = .replace
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
            let rooftopLengths: [CGFloat] = currentMap == .jungle
                ? [600, 440, 520, 740, 460, 680, 420] : [680, 480, 520, 820, 460, 720]
            var length: CGFloat = index == 0 ? 1500 : (currentMap != .twilight
                ? rooftopLengths[(index - 1) % rooftopLengths.count] : 850 - difficulty * 160)
            // Keep the finish line on a wide, safe landing instead of inside a gap.
            if start + length >= finishDistance - 400 {
                length = finishDistance + 600 - start
            }
            let heights: [CGFloat] = currentMap == .jungle ? [0, 60, 135, 55, 150, 85, 30]
                : currentMap == .neon ? [0, 55, 130, 65, 160, 90] : [0, 45, 85, 30]
            let elevation: CGFloat = currentMap != .twilight ? (index == 0 ? 0 : heights[(index - 1) % heights.count])
                : (index < 2 ? 0 : heights[index % heights.count])
            let platform = Platform(start: start, end: start + length, elevation: elevation)
            platforms.append(platform)
            addPlatform(platform)

            if index == 0 {
                addSpikes(at: 650, elevation: 0, count: 2)
            } else if length >= 650 && start + length * 0.52 < finishDistance - 350 {
                // Keep hazards away from the landing and takeoff edges.
                let hazardX = start + length * 0.52
                if index >= 3 && (index % 3 == 0 || currentMap != .twilight && index % 2 == 0) {
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
            let gap: CGFloat = index == 0 ? 85 : (currentMap == .jungle
                ? [CGFloat(120), 145, 130, 155, 110][index % 5]
                : currentMap == .neon ? [CGFloat(100), 120, 100, 140][index % 4] : 95 + difficulty * 45)
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
        courseObjects = course.children.map { node in
            let bounds = node.calculateAccumulatedFrame()
            return CourseObject(node: node, body: node.physicsBody, minX: bounds.minX, maxX: bounds.maxX)
        }
        lastActivationDistance = -.infinity
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
        if currentMap == .neon {
            node.color = SKColor(red: 0.10, green: 0.08, blue: 0.19, alpha: 1)
            decorateRooftop(node, width: width, depth: depth, elevation: platform.elevation)
        }
        if currentMap == .jungle { decorateJunglePlatform(node, width: width, depth: depth) }
        course.addChild(node)
        let edge = SKSpriteNode(color: themeColor, size: CGSize(width: width, height: 4))
        edge.anchorPoint = CGPoint(x: 0, y: 0.5)
        node.addChild(edge)
        guard currentMap == .twilight else { return }
        for x in stride(from: CGFloat(25), to: width, by: 90) {
            let mark = SKSpriteNode(color: .systemMint.withAlphaComponent(0.2), size: CGSize(width: 25, height: 3))
            mark.position = CGPoint(x: x, y: -25)
            node.addChild(mark)
        }
    }

    private func decorateRooftop(_ node: SKSpriteNode, width: CGFloat, depth: CGFloat, elevation: CGFloat) {
        // Bake the opaque facade at game resolution, rather than storing large
        // Retina textures and blending separate windows, signs, and trim each frame.
        let key = "roof-\(Int(width))-\(Int(depth))-\(Int(elevation))"
        if textureCache[key] == nil {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: depth), format: format)
            let image = renderer.image { context in
                let graphics = context.cgContext
                graphics.setFillColor(UIColor(red: 0.10, green: 0.08, blue: 0.19, alpha: 1).cgColor)
                graphics.fill(CGRect(x: 0, y: 0, width: width, height: depth))
                graphics.setFillColor(UIColor(red: 0.25, green: 0.19, blue: 0.36, alpha: 1).cgColor)
                graphics.fill(CGRect(x: 0, y: 0, width: width, height: 18))
                graphics.setFillColor(UIColor.systemPink.withAlphaComponent(0.65).cgColor)
                graphics.fill(CGRect(x: 0, y: 21, width: width, height: 3))
                graphics.setFillColor(UIColor.cyan.withAlphaComponent(0.4).cgColor)
                graphics.fill(CGRect(x: width - 3, y: 0, width: 3, height: depth))
                for column in 0..<Int(width / 46) {
                    for row in 0..<Int((depth - 65) / 42) where (column + row * 3) % 5 != 0 {
                        graphics.fill(CGRect(x: 18 + CGFloat(column) * 46,
                                             y: 47 + CGFloat(row) * 42, width: 16, height: 23))
                    }
                }
                let title = "KAPLAN GAMES" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "AvenirNext-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.systemPink
                ]
                // Align the full text to the right with space before the building edge.
                let titleWidth = title.size(withAttributes: attributes).width
                title.draw(at: CGPoint(x: width - titleWidth - 20, y: 29), withAttributes: attributes)
            }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            textureCache[key] = texture
        }
        node.texture = textureCache[key]
        node.colorBlendFactor = 0
        node.blendMode = .replace
    }

    private func addSpikes(at worldX: CGFloat, elevation: CGFloat, count: Int) {
        for index in 0..<count {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -12, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 38))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.closeSubpath()
            let shape = SKShapeNode(path: path)
            shape.fillColor = currentMap == .jungle ? .systemOrange : .systemPink
            shape.strokeColor = .white.withAlphaComponent(0.65)
            shape.lineWidth = 1.5
            let spike = rasterized(shape, key: currentMap == .jungle ? "jungle-spike" : "spike")
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
        shape.fillColor = currentMap == .jungle ? .systemGreen : .systemPink
        shape.strokeColor = .white
        shape.lineWidth = 2
        let saw = rasterized(shape, key: currentMap == .jungle ? "jungle-saw" : "saw")
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
        for coin in nearbyCoins where !coin.isHidden {
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
            refreshAchievements()
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
        lastActivationDistance = -.infinity
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
            let skinsButton = SKShapeNode(rectOf: CGSize(width: 210, height: 44), cornerRadius: 14)
            skinsButton.name = "skins"
            skinsButton.fillColor = .white.withAlphaComponent(0.12)
            skinsButton.strokeColor = .clear
            skinsButton.position = CGPoint(x: size.width / 2, y: centerY - 90)
            overlay.addChild(skinsButton)
            let label = addLabel("SKINS", size: 16, y: -6, to: skinsButton)
            label.position.x = 0
            label.name = "skins"
            let mapsButton = SKShapeNode(rectOf: CGSize(width: 210, height: 40), cornerRadius: 12)
            mapsButton.name = "maps"
            mapsButton.fillColor = .white.withAlphaComponent(0.12)
            mapsButton.strokeColor = .clear
            mapsButton.position = CGPoint(x: size.width / 2, y: centerY - 140)
            overlay.addChild(mapsButton)
            let mapLabel = addLabel("MAPS", size: 16, y: -6, to: mapsButton)
            mapLabel.position.x = 0
            let achievementButton = SKShapeNode(circleOfRadius: 28)
            achievementButton.name = "achievements"
            achievementButton.fillColor = SKColor(red: 0.12, green: 0.17, blue: 0.25, alpha: 1)
            achievementButton.strokeColor = .systemYellow.withAlphaComponent(0.6)
            achievementButton.lineWidth = 1.5
            achievementButton.position = CGPoint(x: size.width - (view?.safeAreaInsets.right ?? 0) - 48,
                                                y: (view?.safeAreaInsets.bottom ?? 0) + 48)
            overlay.addChild(achievementButton)
            achievementButton.addChild(achievementMedal())
        } else {
            let menu = addLabel("MAIN MENU", size: 15, y: centerY - 90, to: overlay)
            menu.name = "menu"
        }
    }

    private func refreshAchievements() {
        achievementQueue.append(contentsOf: achievements.refresh(wallet: wallet, skins: skins, maps: mapProgress,
                                                                 runCoins: collectedCoins))
        showNextAchievement()
    }

    private func showNextAchievement() {
        guard !showingAchievement, !achievementQueue.isEmpty else { return }
        showingAchievement = true
        let achievement = achievementQueue.removeFirst()
        let width = min(310, size.width - 40)
        let banner = SKShapeNode(rectOf: CGSize(width: width, height: 62), cornerRadius: 14)
        banner.fillColor = SKColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1)
        banner.strokeColor = .systemYellow
        // Keep notifications below the progress and coin HUD.
        banner.position = CGPoint(x: size.width / 2, y: size.height - safeTop - 125)
        banner.alpha = 0
        notifications.addChild(banner)
        let heading = addLabel("ACHIEVEMENT UNLOCKED", size: 10, y: 10, to: banner)
        heading.position.x = 0
        heading.fontColor = .systemYellow
        let title = addLabel(achievement.title, size: 16, y: -13, to: banner)
        title.position.x = 0
        banner.run(.sequence([.fadeIn(withDuration: 0.15), .wait(forDuration: 2),
                              .fadeOut(withDuration: 0.2), .run { [weak self, weak banner] in
            banner?.removeFromParent()
            self?.showingAchievement = false
            self?.showNextAchievement()
        }]))
    }

    private func showAchievements() {
        state = .achievements
        overlay.removeAllChildren()
        hud.isHidden = true
        let shade = SKSpriteNode(color: .black.withAlphaComponent(0.85), size: size)
        shade.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(shade)
        let top = size.height - safeTop - 55
        addLabel("ACHIEVEMENTS", size: 24, y: top, to: overlay)
        let wide = size.width > size.height
        let columns = wide ? 2 : 1
        let rows = Int(ceil(Double(AchievementID.allCases.count) / Double(columns)))
        let spacing = min(108, (top - 100) / CGFloat(rows))
        let cardWidth = min(360, (size.width - CGFloat(columns + 1) * 20) / CGFloat(columns))
        let gridWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * 20
        for (index, id) in AchievementID.allCases.enumerated() {
            let stages = achievements.completedStages(for: id)
            let complete = stages == id.targets.count
            let value = achievements.value(for: id, wallet: wallet, skins: skins, maps: mapProgress)
            let target = id.targets[min(stages, id.targets.count - 1)]
            let card = SKShapeNode(rectOf: CGSize(width: cardWidth, height: spacing - 8), cornerRadius: 12)
            card.position = CGPoint(x: (size.width - gridWidth) / 2 + cardWidth / 2 + CGFloat(index % columns) * (cardWidth + 20),
                                    y: top - 22 - spacing * (CGFloat(index / columns) + 0.5))
            card.fillColor = .white.withAlphaComponent(0.07)
            card.strokeColor = complete ? .systemMint : .white.withAlphaComponent(0.12)
            overlay.addChild(card)
            let title = addLabel(id.title, size: wide ? 14 : 18, y: wide ? 12 : 24, to: card)
            title.position.x = 0
            title.fontColor = complete ? .systemMint : .white
            if id.targets.count == 3 {
                title.horizontalAlignmentMode = .left
                title.position.x = -cardWidth / 2 + 18
                let gap: CGFloat = wide ? 18 : 23
                let radius: CGFloat = wide ? 7 : 9
                let right = cardWidth / 2 - 22
                for index in 0..<3 {
                    let star = achievementStar(earned: index < stages, radius: radius)
                    star.position = CGPoint(x: right - CGFloat(2 - index) * gap, y: title.position.y + 6)
                    card.addChild(star)
                }
            }
            let detail = addLabel(id.detail(target: target), size: wide ? 10 : 11, y: wide ? -2 : 4, to: card)
            detail.position.x = 0
            let statusText = complete ? "COMPLETED" : "\(min(value, target)) / \(target)"
            let status = addLabel(statusText, size: wide ? 10 : 11, y: wide ? -15 : -17, to: card)
            status.position.x = 0
            status.fontColor = .systemYellow
            let barWidth = cardWidth - 36
            let track = SKSpriteNode(color: .white.withAlphaComponent(0.15), size: CGSize(width: barWidth, height: 3))
            track.position.y = wide ? -24 : -33
            card.addChild(track)
            let fill = SKSpriteNode(color: complete ? .systemMint : .systemYellow,
                                    size: CGSize(width: barWidth * min(1, CGFloat(value) / CGFloat(target)), height: 3))
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.position = CGPoint(x: -barWidth / 2, y: track.position.y)
            card.addChild(fill)
        }
        let back = addLabel("MAIN MENU", size: 16, y: (view?.safeAreaInsets.bottom ?? 0) + 25, to: overlay)
        back.name = "menu"
    }

    private func achievementMedal() -> SKNode {
        let icon = SKNode()
        // Explicit depth keeps every part above the button when sibling order is ignored.
        icon.zPosition = 1
        let ribbonPath = CGMutablePath()
        ribbonPath.move(to: CGPoint(x: -12, y: 16))
        ribbonPath.addLine(to: CGPoint(x: -3, y: 16))
        ribbonPath.addLine(to: CGPoint(x: 4, y: 0))
        ribbonPath.addLine(to: CGPoint(x: -4, y: -4))
        ribbonPath.closeSubpath()
        ribbonPath.move(to: CGPoint(x: 3, y: 16))
        ribbonPath.addLine(to: CGPoint(x: 12, y: 16))
        ribbonPath.addLine(to: CGPoint(x: 4, y: -4))
        ribbonPath.addLine(to: CGPoint(x: -4, y: 0))
        ribbonPath.closeSubpath()
        let ribbons = SKShapeNode(path: ribbonPath)
        ribbons.fillColor = SKColor(red: 0.86, green: 0.53, blue: 0.08, alpha: 1)
        ribbons.strokeColor = SKColor(red: 1, green: 0.81, blue: 0.30, alpha: 1)
        ribbons.lineWidth = 1
        icon.addChild(ribbons)

        let medal = SKShapeNode(circleOfRadius: 11)
        medal.position.y = -5
        medal.zPosition = 1
        medal.fillColor = SKColor(red: 1, green: 0.76, blue: 0.12, alpha: 1)
        medal.strokeColor = SKColor(red: 1, green: 0.91, blue: 0.53, alpha: 1)
        medal.lineWidth = 2
        icon.addChild(medal)
        let star = achievementStar(earned: true, radius: 6.5)
        star.zPosition = 1
        star.fillColor = SKColor(red: 0.67, green: 0.36, blue: 0.03, alpha: 1)
        star.strokeColor = .clear
        medal.addChild(star)
        return icon
    }

    private func achievementStar(earned: Bool, radius: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        for point in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(point) * .pi / 5
            let length = point.isMultiple(of: 2) ? radius : radius * 0.45
            let position = CGPoint(x: cos(angle) * length, y: sin(angle) * length)
            if point == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        let star = SKShapeNode(path: path)
        star.fillColor = earned ? SKColor(red: 1, green: 0.77, blue: 0.16, alpha: 1)
            : SKColor(red: 0.22, green: 0.25, blue: 0.30, alpha: 1)
        star.strokeColor = earned ? SKColor(red: 1, green: 0.91, blue: 0.53, alpha: 1)
            : SKColor(red: 0.38, green: 0.41, blue: 0.46, alpha: 1)
        star.lineWidth = 1
        return star
    }

    private func showMaps() {
        state = .maps
        overlay.removeAllChildren()
        hud.isHidden = true
        let shade = SKSpriteNode(color: .black.withAlphaComponent(0.85), size: size)
        shade.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(shade)
        let top = size.height - safeTop - 60
        addLabel("MAPS", size: 28, y: top, to: overlay)
        let spacing = min(140, (top - 80) / CGFloat(ParkourMap.allCases.count))
        for (index, map) in ParkourMap.allCases.enumerated() {
            let card = SKShapeNode(rectOf: CGSize(width: min(350, size.width - 40), height: spacing - 12), cornerRadius: 18)
            card.name = "map:\(map.rawValue)"
            card.position = CGPoint(x: size.width / 2, y: top - 20 - spacing * (CGFloat(index) + 0.5))
            card.fillColor = map == .jungle ? SKColor(red: 0.05, green: 0.20, blue: 0.12, alpha: 1) : map == .neon ? SKColor(red: 0.20, green: 0.07, blue: 0.30, alpha: 1)
                : SKColor(red: 0.09, green: 0.18, blue: 0.26, alpha: 1)
            card.strokeColor = currentMap == map ? .systemMint : .white.withAlphaComponent(0.15)
            overlay.addChild(card)
            let title = addLabel("\(map.number) / \(map.title)", size: 20, y: 20, to: card)
            title.position.x = 0
            let detail = addLabel(map.description, size: 11, y: 0, to: card)
            detail.position.x = 0
            let status = addLabel("BEST \(mapProgress.best(for: map))% · \(currentMap == map ? "SELECTED" : "SELECT")", size: 13, y: -25, to: card)
            status.position.x = 0
            status.fontColor = .systemMint
        }
        let back = addLabel("MAIN MENU", size: 16, y: 35, to: overlay)
        back.name = "menu"
    }

    private func skinColor(_ skin: RunnerSkin) -> SKColor {
        switch skin {
        case .orange: return .systemOrange
        case .mint: return .systemMint
        case .blue: return .systemBlue
        case .violet: return .systemPurple
        case .rose: return .systemPink
        }
    }

    private func showSkins(message: String? = nil) {
        state = .skins
        pendingSkinPurchase = nil
        overlay.removeAllChildren()
        hud.isHidden = true
        let shade = SKSpriteNode(color: .black.withAlphaComponent(0.8), size: size)
        shade.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(shade)
        let balance = addLabel("COINS  \(wallet.balance)", size: 15, y: size.height - safeTop - 40, to: overlay)
        balance.position.x = 28
        balance.horizontalAlignmentMode = .left
        balance.fontColor = .systemYellow

        // Keep the shop compact enough for both portrait and landscape screens.
        let top = size.height - safeTop - 85
        addLabel("SKINS", size: 28, y: top, to: overlay)
        let spacing = min(78, (top - 85) / CGFloat(RunnerSkin.allCases.count))
        let rowWidth = min(330, size.width - 48)
        for (index, skin) in RunnerSkin.allCases.enumerated() {
            let row = SKShapeNode(rectOf: CGSize(width: rowWidth, height: spacing - 6), cornerRadius: 12)
            row.position = CGPoint(x: size.width / 2, y: top - 25 - spacing * (CGFloat(index) + 0.5))
            row.name = "skin:\(skin.rawValue)"
            row.fillColor = .white.withAlphaComponent(0.08)
            row.strokeColor = skins.selected == skin ? .systemMint : .clear
            overlay.addChild(row)
            let preview = SKSpriteNode(color: skinColor(skin), size: CGSize(width: 28, height: 28))
            preview.position.x = -rowWidth / 2 + 28
            row.addChild(preview)
            let title = addLabel(skin.title, size: 15, y: -5, to: row)
            title.horizontalAlignmentMode = .left
            title.position.x = -rowWidth / 2 + 52
            let action = skins.selected == skin ? "EQUIPPED" : skins.owns(skin) ? "EQUIP" : "BUY · \(skin.price)"
            let label = addLabel(action, size: 13, y: -5, to: row)
            label.horizontalAlignmentMode = .right
            label.position.x = rowWidth / 2 - 14
            label.fontColor = skins.selected == skin ? .systemMint : .systemYellow
        }
        let back = addLabel("MAIN MENU", size: 16, y: 35, to: overlay)
        back.name = "menu"
        if let message {
            let note = addLabel(message, size: 13, y: 64, to: overlay)
            note.fontColor = .systemYellow
        }
    }

    private func showPurchaseConfirmation(for skin: RunnerSkin) {
        pendingSkinPurchase = skin
        let dialog = SKNode()
        dialog.name = "purchaseDialog"
        dialog.zPosition = 100
        overlay.addChild(dialog)
        let dim = SKSpriteNode(color: .black.withAlphaComponent(0.7), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dialog.addChild(dim)

        let panel = SKShapeNode(rectOf: CGSize(width: min(330, size.width - 32), height: 260), cornerRadius: 22)
        panel.fillColor = SKColor(red: 0.12, green: 0.16, blue: 0.25, alpha: 1)
        panel.strokeColor = .white.withAlphaComponent(0.2)
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dialog.addChild(panel)
        let title = addLabel("Buy \(skin.title)?", size: 24, y: 85, to: panel)
        title.position.x = 0
        let preview = SKSpriteNode(color: skinColor(skin), size: CGSize(width: 38, height: 38))
        preview.position.y = 44
        panel.addChild(preview)
        let price = addLabel("1,000 COINS", size: 18, y: 2, to: panel)
        price.position.x = 0
        price.fontColor = .systemYellow
        let affordable = wallet.balance >= skin.price
        let note = addLabel(affordable ? "Balance: \(wallet.balance) coins" : "Not enough coins · Balance: \(wallet.balance)", size: 12, y: -25, to: panel)
        note.position.x = 0

        for (name, text, x) in [("cancelPurchase", "CANCEL", CGFloat(-73)), ("confirmPurchase", "BUY", CGFloat(73))] {
            let button = SKShapeNode(rectOf: CGSize(width: 132, height: 46), cornerRadius: 12)
            button.name = name
            button.position = CGPoint(x: x, y: -79)
            button.fillColor = name == "confirmPurchase" ? (affordable ? .systemMint : .darkGray) : .gray
            button.strokeColor = .clear
            panel.addChild(button)
            let label = addLabel(text, size: 15, y: -5, to: button)
            label.position.x = 0
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
            // Walk ancestors so tapping a preview or label activates its entire row.
            let names = nodes(at: touch.location(in: self)).flatMap { node -> [String] in
                var names: [String] = []
                var current: SKNode? = node
                while let item = current {
                    if let name = item.name { names.append(name) }
                    current = item.parent
                }
                return names
            }
            // A modal consumes all touches, including taps on the dimmed shop behind it.
            if let skin = pendingSkinPurchase {
                if names.contains("cancelPurchase") {
                    showSkins()
                } else if names.contains("confirmPurchase"), wallet.balance >= skin.price {
                    let success = skins.selectOrBuy(skin, wallet: wallet)
                    player.color = skinColor(skins.selected)
                    updateCoinLabel()
                    showSkins(message: success ? "Purchased and equipped" : "Not enough coins")
                    if success { refreshAchievements() }
                }
                return
            }
            if state == .skins, let name = names.first(where: { $0.hasPrefix("skin:") }),
               let skin = RunnerSkin(rawValue: String(name.dropFirst(5))) {
                if skins.owns(skin) {
                    skins.selectOrBuy(skin, wallet: wallet)
                    player.color = skinColor(skins.selected)
                    showSkins()
                } else {
                    showPurchaseConfirmation(for: skin)
                }
                return
            }
            if state == .maps, let name = names.first(where: { $0.hasPrefix("map:") }),
               let map = ParkourMap(rawValue: String(name.dropFirst(4))) {
                mapProgress.select(map)
                rebuild()
                return
            }
            if names.contains("achievements") {
                showAchievements()
            } else if names.contains("maps") {
                showMaps()
            } else if names.contains("skins") {
                showSkins()
            } else if names.contains("menu") {
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
        updateActiveObjects()
        for node in movingHazards where !node.isHidden {
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

    private func updateActiveObjects() {
        // Recheck in small distance chunks, with generous margins to avoid visible pop-in.
        guard abs(distance - lastActivationDistance) >= 64 else { return }
        lastActivationDistance = distance
        let left = distance - 200
        let right = distance + size.width + 256
        for object in courseObjects {
            let active = object.maxX >= left && object.minX <= right
            // Coin visibility records collection, so leave it untouched here.
            if object.node.name != "coin" { object.node.isHidden = !active }
            if active {
                if object.node.physicsBody == nil, let body = object.body {
                    object.node.physicsBody = body
                }
            } else if object.node.physicsBody != nil {
                object.node.physicsBody = nil
            }
        }
        nearbyCoins = coinNodes.filter { abs($0.position.x - runnerX - distance) < 200 }
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
        mapProgress.record(won ? 100 : Int(min(1, distance / finishDistance) * 100), for: currentMap)
        refreshAchievements()
        state = won ? .won : .lost
        player.physicsBody?.velocity = .zero
        player.physicsBody?.isDynamic = false
        showOverlay(title: won ? "COMPLETED!" : "TRY AGAIN", subtitle: "\(Int(min(1, distance / finishDistance) * 100))% · COINS \(collectedCoins)", button: "RESTART")
    }
}
