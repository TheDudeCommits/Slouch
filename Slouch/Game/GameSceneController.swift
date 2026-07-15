import Foundation
import SceneKit
import UIKit

struct GameSnapshot: Equatable {
    var score: Int = 0
    var hull: Double = 100
    var energy: Double = 60
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 180
    var hazardsCleared: Int = 0
    var pickups: Int = 0
    var multiplier: Double = 1
    var neutralQuality: Double = 1
    var smoothness: Double = 1
    var trackingQuality: Double = 1
    var cue: MovementCue = .neutral
    var cueProgress: Double = 0
    var isPaused = false
    var isFinished = false
    var statusMessage: String?

    var remaining: TimeInterval { max(0, duration - elapsed) }
}

enum GameAction: Equatable {
    case nod
    case shieldBoost
    case rollLeft
    case rollRight
    case shoulderSet
    case abruptMotion
}

struct GameControlInput: Equatable {
    var horizontal: Double = 0
    var vertical: Double = 0
    var neutralQuality: Double = 1
    var motionSmoothness: Double = 1
    var trackingQuality: Double = 1
    var trackingAvailable = true
}

enum GameSceneEvent {
    case pickup
    case collision
    case nearMiss
    case boost
    case roll
    case courseComplete
}

final class GameSceneController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let pointOfView = SCNNode()
    let mode: GameMode
    let theme: GameTheme
    let courseDuration: TimeInterval
    let reduceMotion: Bool

    var onSnapshot: ((GameSnapshot) -> Void)?
    var onEvent: ((GameSceneEvent) -> Void)?

    private let stateLock = NSLock()
    private var input = GameControlInput()
    private var pendingActions: [GameAction] = []
    private var paused = false
    private var endedEarly = false

    private let world = SCNNode()
    private let ship = SCNNode()
    private let shipBody = SCNNode()
    private let cameraRig = SCNNode()
    private let planet = SCNNode()
    private var obstacles: [ObstacleNode] = []
    private var techEvents: [TechEvent] = []
    private var nextTechEvent = 0

    private var lastUpdateTime: TimeInterval?
    private var lastSnapshotTime: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var casualSpawnTimer: TimeInterval = 1
    private var shipX: Float = 0
    private var shipY: Float = 0
    private var laneY: Float = 0
    private var boostRemaining: TimeInterval = 0
    private var shieldRemaining: TimeInterval = 0
    private var rollRemaining: TimeInterval = 0
    private var rollDirection: Float = 0
    private var wobbleRemaining: TimeInterval = 0
    private var hull: Double = 100
    private var energy: Double = 60
    private var hazardsCleared = 0
    private var pickups = 0
    private var collisions = 0
    private var softAbruptEvents = 0
    private var controlledMovements = 0
    private var neutralTime: TimeInterval = 0
    private var trackingAccumulator: Double = 0
    private var trackingSampleTime: TimeInterval = 0
    private var smoothnessAccumulator: Double = 0
    private var smoothnessSampleTime: TimeInterval = 0
    private var leftActions = 0
    private var rightActions = 0
    private var currentCue: MovementCue = .neutral
    private var cueProgress: Double = 0
    private var finished = false
    private var randomIndex = 0

    init(mode: GameMode, theme: GameTheme, reduceMotion: Bool = false) {
        self.mode = mode
        self.theme = theme
        self.reduceMotion = reduceMotion
        courseDuration = mode == .techNeck ? 180 : 90
        super.init()
        configureScene()
    }

    func setInput(_ input: GameControlInput) {
        stateLock.lock()
        self.input = input
        stateLock.unlock()
    }

    func trigger(_ action: GameAction) {
        stateLock.lock()
        pendingActions.append(action)
        stateLock.unlock()
    }

    func setPaused(_ isPaused: Bool) {
        stateLock.lock()
        paused = isPaused
        stateLock.unlock()
    }

    func endFlight() {
        stateLock.lock()
        endedEarly = true
        stateLock.unlock()
    }

    func makeRunRecord(usedCameraControls: Bool, leaderboardEligible: Bool) -> RunRecord {
        let metrics = makeMetrics()
        return RunRecord(
            mode: mode,
            score: finalScore(completed: finished && !endedEarly),
            duration: elapsed,
            hazardsCleared: hazardsCleared,
            pickups: pickups,
            completedCourse: finished && !endedEarly,
            usedCameraControls: usedCameraControls,
            leaderboardEligible: leaderboardEligible && finished && !endedEarly,
            metrics: metrics
        )
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard !finished else { return }
        guard let lastUpdateTime else {
            self.lastUpdateTime = time
            return
        }

        let dt = min(max(time - lastUpdateTime, 0), 1.0 / 15.0)
        self.lastUpdateTime = time

        stateLock.lock()
        let currentInput = input
        let actions = pendingActions
        pendingActions.removeAll(keepingCapacity: true)
        let shouldPause = paused
        let shouldEnd = endedEarly
        stateLock.unlock()

        if shouldEnd {
            finishCourse(completed: false)
            return
        }

        if shouldPause {
            publishSnapshot(force: false, status: "Flight paused")
            return
        }

        elapsed += dt
        process(actions: actions)
        updateTimers(dt: dt)
        updateShip(input: currentInput, dt: dt)
        updateWorld(input: currentInput, dt: dt)
        updateCourse(dt: dt)

        if elapsed >= courseDuration || hull <= 0 {
            finishCourse(completed: elapsed >= courseDuration && hull > 0)
        } else {
            publishSnapshot(force: false, status: currentInput.trackingAvailable ? nil : "Tracking paused · hold still")
        }
    }

    private func configureScene() {
        scene.rootNode.addChildNode(world)
        scene.background.contents = palette.background
        scene.fogColor = palette.fog
        scene.fogStartDistance = 46
        scene.fogEndDistance = 125
        scene.fogDensityExponent = 0.7

        configureCamera()
        configureLights()
        configureStarfield()
        configurePlanet()
        configureShip()
        configureDust()
        techEvents = Self.makeTechEvents()
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 58
        camera.zNear = 0.05
        camera.zFar = 220
        camera.wantsHDR = true
        camera.bloomIntensity = reduceMotion ? 0.12 : 0.32
        camera.bloomThreshold = 1.15
        camera.bloomBlurRadius = 5
        camera.wantsExposureAdaptation = true
        camera.exposureOffset = -0.55
        camera.vignettingIntensity = 0.45
        camera.vignettingPower = 0.7

        pointOfView.camera = camera
        pointOfView.position = SCNVector3(0, 2.7, 12.8)
        pointOfView.eulerAngles.x = -0.17
        cameraRig.addChildNode(pointOfView)
        world.addChildNode(cameraRig)
    }

    private func configureLights() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.23, green: 0.28, blue: 0.45, alpha: 1)
        ambient.intensity = 185
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        world.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(red: 0.63, green: 0.76, blue: 1, alpha: 1)
        key.intensity = 650
        key.castsShadow = true
        key.shadowRadius = 8
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.7, -0.65, 0)
        world.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.color = palette.glow
        rim.intensity = 280
        rim.attenuationEndDistance = 45
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-12, 8, -18)
        world.addChildNode(rimNode)
    }

    private func configureStarfield() {
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        let count = 420
        for index in 0..<count {
            let a = Float(index) * 2.399963
            let radius = 8 + Float((index * 31) % 85) / 2
            let x = cos(a) * radius
            let y = sin(a * 1.37) * (7 + Float(index % 23) / 2)
            let z = -Float(8 + (index * 47) % 150)
            vertices.append(SCNVector3(x, y, z))
            colors.append(index % 13 == 0 ? palette.glow : UIColor.white.withAlphaComponent(0.72))
        }

        let source = SCNGeometrySource(vertices: vertices)
        let colorData = colors.flatMap { color -> [Float] in
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [Float(r), Float(g), Float(b), Float(a)]
        }.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        let indices = (0..<count).map { UInt16($0) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 1.7
        element.minimumPointScreenSpaceRadius = 0.7
        element.maximumPointScreenSpaceRadius = 3.2
        let geometry = SCNGeometry(sources: [source, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.blendMode = .add
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        world.addChildNode(SCNNode(geometry: geometry))
    }

    private func configurePlanet() {
        let sphere = SCNSphere(radius: 18)
        sphere.segmentCount = 96
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = palette.planet
        material.emission.contents = palette.planet
        material.emission.intensity = 0.13
        material.roughness.contents = 0.72
        sphere.materials = [material]
        planet.geometry = sphere
        planet.position = SCNVector3(23, 17, -98)
        planet.scale = SCNVector3(1, 0.94, 1)
        world.addChildNode(planet)

        let halo = SCNTorus(ringRadius: 22, pipeRadius: 0.17)
        let haloMaterial = SCNMaterial()
        haloMaterial.lightingModel = .constant
        haloMaterial.diffuse.contents = palette.glow.withAlphaComponent(0.32)
        haloMaterial.emission.contents = palette.glow
        haloMaterial.blendMode = .add
        halo.materials = [haloMaterial]
        let haloNode = SCNNode(geometry: halo)
        haloNode.eulerAngles = SCNVector3(1.1, 0.2, 0.45)
        planet.addChildNode(haloNode)
    }

    private func configureShip() {
        ship.position = SCNVector3(0, 0, 0)
        world.addChildNode(ship)
        ship.addChildNode(shipBody)

        let bodyGeometry = SCNCapsule(capRadius: 0.38, height: 2.45)
        bodyGeometry.radialSegmentCount = 32
        bodyGeometry.heightSegmentCount = 10
        let pearl = SCNMaterial()
        pearl.lightingModel = .physicallyBased
        pearl.diffuse.contents = UIColor(red: 0.52, green: 0.61, blue: 0.75, alpha: 1)
        pearl.metalness.contents = 0.34
        pearl.roughness.contents = 0.3
        bodyGeometry.materials = [pearl]
        let body = SCNNode(geometry: bodyGeometry)
        body.eulerAngles.x = .pi / 2
        body.position.z = -0.15
        body.scale = SCNVector3(1, 0.78, 1)
        shipBody.addChildNode(body)

        let wingGeometry = Self.makeWingGeometry()
        wingGeometry.materials = [pearl]
        let wings = SCNNode(geometry: wingGeometry)
        wings.position = SCNVector3(0, -0.08, 0.12)
        shipBody.addChildNode(wings)

        let canopy = SCNSphere(radius: 0.34)
        canopy.segmentCount = 32
        let canopyMaterial = SCNMaterial()
        canopyMaterial.lightingModel = .physicallyBased
        canopyMaterial.diffuse.contents = UIColor(red: 0.035, green: 0.07, blue: 0.12, alpha: 1)
        canopyMaterial.metalness.contents = 0.75
        canopyMaterial.roughness.contents = 0.13
        canopy.materials = [canopyMaterial]
        let canopyNode = SCNNode(geometry: canopy)
        canopyNode.scale = SCNVector3(0.72, 0.34, 1.3)
        canopyNode.position = SCNVector3(0, 0.32, -0.42)
        shipBody.addChildNode(canopyNode)

        let seam = SCNBox(width: 0.035, height: 0.025, length: 1.55, chamferRadius: 0.015)
        let seamMaterial = SCNMaterial()
        seamMaterial.lightingModel = .constant
        seamMaterial.diffuse.contents = UIColor(red: 0.91, green: 0.72, blue: 0.35, alpha: 1)
        seamMaterial.emission.contents = UIColor(red: 0.7, green: 0.42, blue: 0.12, alpha: 1)
        seam.materials = [seamMaterial]
        let seamNode = SCNNode(geometry: seam)
        seamNode.position = SCNVector3(0, 0.38, -0.05)
        shipBody.addChildNode(seamNode)

        addEngine(at: SCNVector3(-0.48, -0.12, 0.96))
        addEngine(at: SCNVector3(0.48, -0.12, 0.96))
    }

    private func addEngine(at position: SCNVector3) {
        let nozzle = SCNCylinder(radius: 0.1, height: 0.18)
        nozzle.radialSegmentCount = 18
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = palette.glow
        material.emission.contents = palette.glow
        nozzle.materials = [material]
        let node = SCNNode(geometry: nozzle)
        node.eulerAngles.x = .pi / 2
        node.position = position
        shipBody.addChildNode(node)

        let trail = SCNParticleSystem()
        trail.birthRate = 105
        trail.particleLifeSpan = 0.72
        trail.particleLifeSpanVariation = 0.18
        trail.particleSize = 0.045
        trail.particleSizeVariation = 0.025
        trail.particleColor = palette.glow.withAlphaComponent(0.85)
        trail.particleColorVariation = SCNVector4(0.14, 0.08, 0.2, 0)
        trail.particleVelocity = 3.4
        trail.particleVelocityVariation = 0.7
        trail.spreadingAngle = 3
        trail.birthDirection = .constant
        trail.emittingDirection = SCNVector3(0, 0, 1)
        trail.blendMode = .additive
        trail.isLightingEnabled = false
        node.addParticleSystem(trail)
    }

    private func configureDust() {
        let dust = SCNParticleSystem()
        dust.birthRate = reduceMotion ? 14 : 48
        dust.particleLifeSpan = 5.2
        dust.particleLifeSpanVariation = 1.4
        dust.particleSize = 0.012
        dust.particleSizeVariation = 0.008
        dust.particleColor = UIColor.white.withAlphaComponent(0.42)
        dust.particleVelocity = 14
        dust.particleVelocityVariation = 3
        dust.emitterShape = SCNBox(width: 13, height: 20, length: 1, chamferRadius: 0)
        dust.birthLocation = .volume
        dust.birthDirection = .constant
        dust.emittingDirection = SCNVector3(0, 0, 1)
        dust.blendMode = .additive
        dust.isLightingEnabled = false
        let node = SCNNode()
        node.position = SCNVector3(0, 0, -65)
        node.addParticleSystem(dust)
        world.addChildNode(node)
    }

    private func process(actions: [GameAction]) {
        for action in actions {
            switch action {
            case .nod:
                laneY = laneY < -0.6 ? 0 : -1.35
                controlledMovements += 1
            case .shieldBoost:
                guard energy >= 14 else { continue }
                boostRemaining = 0.78
                shieldRemaining = 0.92
                energy -= 14
                controlledMovements += 1
                emit(.boost)
            case .rollLeft:
                rollRemaining = 0.58
                rollDirection = -1
                leftActions += 1
                controlledMovements += 1
                emit(.roll)
            case .rollRight:
                rollRemaining = 0.58
                rollDirection = 1
                rightActions += 1
                controlledMovements += 1
                emit(.roll)
            case .shoulderSet:
                energy = min(100, energy + 15)
                hull = min(100, hull + 8)
                controlledMovements += 1
            case .abruptMotion:
                softAbruptEvents += 1
                wobbleRemaining = 0.45
            }
        }
    }

    private func updateTimers(dt: TimeInterval) {
        boostRemaining = max(0, boostRemaining - dt)
        shieldRemaining = max(0, shieldRemaining - dt)
        rollRemaining = max(0, rollRemaining - dt)
        wobbleRemaining = max(0, wobbleRemaining - dt)
    }

    private func updateShip(input: GameControlInput, dt: TimeInterval) {
        let sensitivity = Float(1 - exp(-dt / 0.13))
        let targetX = Float(input.horizontal) * 3.25 + (rollRemaining > 0 ? rollDirection * 1.05 : 0)
        let verticalInput = mode == .casual ? Float(input.vertical) * 1.8 : laneY
        shipX += (targetX - shipX) * sensitivity
        shipY += (verticalInput - shipY) * sensitivity
        shipX = min(max(shipX, -3.55), 3.55)
        shipY = min(max(shipY, -2), 2)

        let wobble = !reduceMotion && wobbleRemaining > 0 ? sin(Float(elapsed) * 32) * 0.14 : 0
        ship.position = SCNVector3(shipX, shipY + wobble, 0)
        let rollProgress = Float(1 - rollRemaining / 0.58)
        let rollVisual = rollRemaining > 0
            ? (reduceMotion
                ? rollDirection * sin(rollProgress * .pi) * 0.18
                : rollDirection * .pi * rollProgress * 2)
            : 0
        shipBody.eulerAngles.z = -Float(input.horizontal) * (reduceMotion ? 0.08 : 0.19) + rollVisual
        shipBody.eulerAngles.x = Float(input.vertical) * 0.05
        shipBody.position.z = boostRemaining > 0 ? -0.42 : 0

        let cameraEase = Float(1 - exp(-dt / 0.32))
        cameraRig.position.x += (shipX * 0.22 - cameraRig.position.x) * cameraEase
        cameraRig.position.y += (shipY * 0.14 - cameraRig.position.y) * cameraEase
        let cameraRoll = reduceMotion ? 0 : -shipBody.eulerAngles.z * 0.12
        cameraRig.eulerAngles.z += (cameraRoll - cameraRig.eulerAngles.z) * cameraEase

        if input.neutralQuality > 0.72 {
            neutralTime += dt
            energy = min(100, energy + dt * 5)
        }
        if input.trackingAvailable {
            trackingAccumulator += input.trackingQuality * dt
            trackingSampleTime += dt
            smoothnessAccumulator += input.motionSmoothness * dt
            smoothnessSampleTime += dt
        }
    }

    private func updateWorld(input: GameControlInput, dt: TimeInterval) {
        let speed = Float(12.5 + min(elapsed / 35, 3.8) + (boostRemaining > 0 ? 8 : 0))
        planet.eulerAngles.y += Float(dt) * 0.012

        for obstacle in obstacles {
            obstacle.position.z += speed * Float(dt)
            let spinScale: Float = reduceMotion ? 0.18 : 1
            obstacle.eulerAngles.x += obstacle.spin.x * Float(dt) * spinScale
            obstacle.eulerAngles.y += obstacle.spin.y * Float(dt) * spinScale
            obstacle.eulerAngles.z += obstacle.spin.z * Float(dt) * spinScale

            guard !obstacle.resolved, obstacle.position.z >= -0.25 else { continue }
            resolve(obstacle: obstacle)
        }

        obstacles.removeAll { obstacle in
            if obstacle.position.z > 11 {
                obstacle.removeFromParentNode()
                return true
            }
            return false
        }
    }

    private func updateCourse(dt: TimeInterval) {
        if mode == .casual {
            casualSpawnTimer -= dt
            if casualSpawnTimer <= 0 {
                spawnCasualObstacle()
                casualSpawnTimer = max(0.88, 1.6 - elapsed / 180)
            }
            currentCue = .neutral
            cueProgress = 0
            return
        }

        while nextTechEvent < techEvents.count, elapsed >= max(0, techEvents[nextTechEvent].time - 4.7) {
            spawn(event: techEvents[nextTechEvent])
            nextTechEvent += 1
        }

        if let event = techEvents.first(where: { elapsed >= $0.time - 2.6 && elapsed <= $0.time + 0.8 }) {
            currentCue = event.cue
            cueProgress = min(max((elapsed - (event.time - 2.6)) / 3.4, 0), 1)
        } else if elapsed < 8 || (elapsed >= 94 && elapsed < 112) || elapsed >= 160 {
            currentCue = .neutral
            cueProgress = min(1, elapsed < 8 ? elapsed / 8 : 0.7)
        } else {
            currentCue = .neutral
            cueProgress = 0
        }
    }

    private func spawnCasualObstacle() {
        randomIndex += 1
        let seed = randomIndex * 37
        let x = Float((seed % 63) - 31) / 10
        let y = Float(((seed * 7) % 31) - 15) / 10
        let kind: ObstacleKind
        switch seed % 10 {
        case 0: kind = .pickup
        case 1: kind = .gate
        case 2: kind = .drone
        case 3: kind = .laser
        default: kind = .asteroid
        }
        addObstacle(kind: kind, x: x, y: y, cue: .neutral)
    }

    private func spawn(event: TechEvent) {
        addObstacle(kind: event.kind, x: event.x, y: event.y, cue: event.cue)
    }

    private func addObstacle(kind: ObstacleKind, x: Float, y: Float, cue: MovementCue) {
        let obstacle = ObstacleNode(kind: kind, palette: palette, seed: randomIndex + obstacles.count * 11)
        obstacle.position = SCNVector3(x, y, -60)
        if kind == .laser { obstacle.safeLaneY = y }
        obstacle.cue = cue
        obstacles.append(obstacle)
        world.addChildNode(obstacle)
    }

    private func resolve(obstacle: ObstacleNode) {
        obstacle.resolved = true
        let dx = shipX - obstacle.position.x
        let dy = shipY - obstacle.position.y
        let distance = sqrt(dx * dx + dy * dy)
        let protected = shieldRemaining > 0 || rollRemaining > 0
        var success = false

        switch obstacle.kind {
        case .pickup:
            if distance < 1.25 {
                pickups += 1
                energy = min(100, energy + 12)
                obstacle.collect()
                emit(.pickup)
            }
            return
        case .asteroid:
            success = protected || distance > obstacle.collisionRadius + 0.62
        case .drone:
            success = protected || distance > 1.15
        case .gate:
            success = mode == .casual ? distance < 1.65 : boostRemaining > 0
        case .laser:
            success = rollRemaining > 0 || abs(shipY - obstacle.safeLaneY) < 0.72
        }

        if success {
            hazardsCleared += 1
            if distance < obstacle.collisionRadius + 1.1 {
                emit(.nearMiss)
            }
            obstacle.clear()
        } else {
            collisions += 1
            hull = max(0, hull - obstacle.damage)
            obstacle.impact()
            emit(.collision)
        }
    }

    private func publishSnapshot(force: Bool, status: String?) {
        guard force || elapsed - lastSnapshotTime >= 0.1 else { return }
        lastSnapshotTime = elapsed
        let metrics = makeMetrics()
        let completed = finished && !endedEarly
        let snapshot = GameSnapshot(
            score: finalScore(completed: completed),
            hull: hull,
            energy: energy,
            elapsed: elapsed,
            duration: courseDuration,
            hazardsCleared: hazardsCleared,
            pickups: pickups,
            multiplier: 1 + 0.5 * qualityScore(metrics: metrics),
            neutralQuality: metrics.neutralAccuracy,
            smoothness: metrics.smoothness,
            trackingQuality: metrics.trackingQuality,
            cue: currentCue,
            cueProgress: cueProgress,
            isPaused: paused,
            isFinished: finished,
            statusMessage: status
        )
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot)
        }
    }

    private func finishCourse(completed: Bool) {
        guard !finished else { return }
        finished = true
        if !completed { endedEarly = true }
        publishSnapshot(force: true, status: completed ? "Journey complete" : "Flight complete")
        if completed { emit(.courseComplete) }
    }

    private func makeMetrics() -> RunMetrics {
        let balance: Double
        let directionalTotal = leftActions + rightActions
        if directionalTotal == 0 {
            balance = 1
        } else {
            balance = 1 - Double(abs(leftActions - rightActions)) / Double(directionalTotal)
        }
        let measuredSmoothness = smoothnessSampleTime > 0
            ? smoothnessAccumulator / smoothnessSampleTime
            : 1
        return RunMetrics(
            neutralAccuracy: elapsed > 0 ? min(max(neutralTime / elapsed, 0), 1) : 1,
            smoothness: min(max(measuredSmoothness - Double(softAbruptEvents) * 0.04, 0), 1),
            leftRightBalance: balance,
            controlledMovements: controlledMovements,
            trackingQuality: trackingSampleTime > 0 ? min(max(trackingAccumulator / trackingSampleTime, 0), 1) : 1
        )
    }

    private func qualityScore(metrics: RunMetrics) -> Double {
        0.32 * metrics.smoothness
            + 0.27 * metrics.neutralAccuracy
            + 0.14 * metrics.leftRightBalance
            + 0.27 * metrics.trackingQuality
    }

    private func finalScore(completed: Bool) -> Int {
        let raw = Int(elapsed * 10) + hazardsCleared * 60 + pickups * 25 + (completed ? 250 : 0)
        return Int((Double(raw) * (1 + 0.5 * qualityScore(metrics: makeMetrics()))).rounded())
    }

    private func emit(_ event: GameSceneEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    private var palette: ScenePalette { ScenePalette(theme: theme) }

    private static func makeWingGeometry() -> SCNGeometry {
        let vertices: [SCNVector3] = [
            SCNVector3(0, 0.08, -1.16),
            SCNVector3(-2.35, -0.08, 0.14),
            SCNVector3(-0.62, -0.16, 0.92),
            SCNVector3(0, -0.06, 0.72),
            SCNVector3(2.35, -0.08, 0.14),
            SCNVector3(0.62, -0.16, 0.92)
        ]
        let normals = vertices.map { _ in SCNVector3(0, 1, 0) }
        let indices: [Int32] = [0, 1, 2, 0, 2, 3, 0, 3, 5, 0, 5, 4]
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial?.isDoubleSided = true
        return geometry
    }

    private static func makeTechEvents() -> [TechEvent] {
        let yawTimes: [TimeInterval] = [13, 18, 23, 28, 33, 37]
        var events = yawTimes.enumerated().map { index, time in
            let left = index.isMultiple(of: 2)
            return TechEvent(time: time, cue: left ? .steerLeft : .steerRight, kind: .asteroid, x: left ? 1.25 : -1.25, y: 0)
        }
        events += [44, 52, 61].map { TechEvent(time: $0, cue: .retract, kind: .gate, x: 0, y: 0) }
        events += [
            TechEvent(time: 71, cue: .bendLeft, kind: .laser, x: 0, y: -0.85),
            TechEvent(time: 78, cue: .bendRight, kind: .laser, x: 0, y: 0.85),
            TechEvent(time: 85, cue: .bendLeft, kind: .laser, x: 0, y: -0.85),
            TechEvent(time: 92, cue: .bendRight, kind: .laser, x: 0, y: 0.85)
        ]
        events += [118, 125, 132, 139].map { TechEvent(time: $0, cue: .nod, kind: .asteroid, x: 0, y: 0.15) }
        events += [
            TechEvent(time: 149, cue: .shoulderSet, kind: .pickup, x: -0.7, y: 0),
            TechEvent(time: 157, cue: .shoulderSet, kind: .pickup, x: 0.7, y: 0)
        ]
        return events.sorted { $0.time < $1.time }
    }
}

private struct TechEvent {
    let time: TimeInterval
    let cue: MovementCue
    let kind: ObstacleKind
    let x: Float
    let y: Float
}

private enum ObstacleKind: Equatable {
    case asteroid
    case gate
    case drone
    case laser
    case pickup
}

private struct ScenePalette {
    let background: UIColor
    let fog: UIColor
    let glow: UIColor
    let accent: UIColor
    let planet: UIColor

    init(theme: GameTheme) {
        switch theme {
        case .luminousFrontier, .jungleRun:
            background = UIColor(red: 0.018, green: 0.032, blue: 0.085, alpha: 1)
            fog = UIColor(red: 0.045, green: 0.06, blue: 0.14, alpha: 1)
            glow = UIColor(red: 0.37, green: 0.84, blue: 0.80, alpha: 1)
            accent = UIColor(red: 0.58, green: 0.53, blue: 0.91, alpha: 1)
            planet = UIColor(red: 0.24, green: 0.19, blue: 0.47, alpha: 1)
        case .auroraDrift:
            background = UIColor(red: 0.01, green: 0.055, blue: 0.08, alpha: 1)
            fog = UIColor(red: 0.02, green: 0.12, blue: 0.14, alpha: 1)
            glow = UIColor(red: 0.28, green: 0.95, blue: 0.76, alpha: 1)
            accent = UIColor(red: 0.32, green: 0.62, blue: 0.95, alpha: 1)
            planet = UIColor(red: 0.08, green: 0.32, blue: 0.36, alpha: 1)
        case .solarEmber:
            background = UIColor(red: 0.075, green: 0.025, blue: 0.045, alpha: 1)
            fog = UIColor(red: 0.12, green: 0.045, blue: 0.06, alpha: 1)
            glow = UIColor(red: 1, green: 0.66, blue: 0.28, alpha: 1)
            accent = UIColor(red: 0.93, green: 0.31, blue: 0.28, alpha: 1)
            planet = UIColor(red: 0.45, green: 0.12, blue: 0.10, alpha: 1)
        }
    }
}

private final class ObstacleNode: SCNNode {
    let kind: ObstacleKind
    let collisionRadius: Float
    let damage: Double
    var safeLaneY: Float = 0
    var resolved = false
    var cue: MovementCue = .neutral
    let spin: SCNVector3

    init(kind: ObstacleKind, palette: ScenePalette, seed: Int) {
        self.kind = kind
        switch kind {
        case .asteroid:
            collisionRadius = 0.85 + Float(seed % 7) * 0.11
            damage = 24
        case .gate:
            collisionRadius = 2.2
            damage = 18
        case .drone:
            collisionRadius = 0.9
            damage = 30
        case .laser:
            collisionRadius = 3.2
            damage = 28
        case .pickup:
            collisionRadius = 0.55
            damage = 0
        }
        spin = SCNVector3(Float((seed % 5) + 1) * 0.11, Float((seed % 7) + 1) * 0.09, Float((seed % 3) + 1) * 0.07)
        super.init()
        build(kind: kind, palette: palette, seed: seed)
    }

    required init?(coder: NSCoder) { nil }

    func collect() {
        runAction(.group([.scale(to: 0.02, duration: 0.22), .fadeOut(duration: 0.18)]))
    }

    func clear() {
        runAction(.fadeOpacity(to: 0.38, duration: 0.35))
    }

    func impact() {
        runAction(.sequence([
            .scale(to: 1.18, duration: 0.08),
            .fadeOpacity(to: 0.16, duration: 0.26)
        ]))
    }

    private func build(kind: ObstacleKind, palette: ScenePalette, seed: Int) {
        switch kind {
        case .asteroid:
            let geometry = Self.asteroidGeometry(radius: CGFloat(collisionRadius), seed: seed)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(red: 0.24, green: 0.28, blue: 0.34, alpha: 1)
            material.emission.contents = palette.glow
            material.emission.intensity = 0.045
            material.roughness.contents = 0.9
            material.metalness.contents = 0.08
            geometry.materials = [material]
            addChildNode(SCNNode(geometry: geometry))

            let vein = SCNTorus(ringRadius: CGFloat(collisionRadius * 0.62), pipeRadius: 0.018)
            let veinMaterial = SCNMaterial()
            veinMaterial.lightingModel = .constant
            veinMaterial.diffuse.contents = palette.glow.withAlphaComponent(0.55)
            veinMaterial.emission.contents = palette.glow
            vein.materials = [veinMaterial]
            let veinNode = SCNNode(geometry: vein)
            veinNode.eulerAngles = SCNVector3(0.8, 0.5, 0.2)
            addChildNode(veinNode)

        case .gate:
            let torus = SCNTorus(ringRadius: 2.45, pipeRadius: 0.18)
            torus.ringSegmentCount = 72
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(red: 0.28, green: 0.32, blue: 0.42, alpha: 1)
            material.metalness.contents = 0.75
            material.roughness.contents = 0.22
            material.emission.contents = palette.accent
            material.emission.intensity = 0.34
            torus.materials = [material]
            addChildNode(SCNNode(geometry: torus))

            let field = SCNCylinder(radius: 2.22, height: 0.025)
            field.radialSegmentCount = 72
            let fieldMaterial = SCNMaterial()
            fieldMaterial.lightingModel = .constant
            fieldMaterial.diffuse.contents = palette.accent.withAlphaComponent(0.16)
            fieldMaterial.emission.contents = palette.accent.withAlphaComponent(0.4)
            fieldMaterial.transparency = 0.42
            fieldMaterial.blendMode = .add
            field.materials = [fieldMaterial]
            let fieldNode = SCNNode(geometry: field)
            fieldNode.eulerAngles.x = .pi / 2
            addChildNode(fieldNode)

        case .drone:
            let core = SCNSphere(radius: 0.42)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1)
            material.metalness.contents = 0.82
            material.roughness.contents = 0.18
            material.emission.contents = palette.accent
            material.emission.intensity = 0.24
            core.materials = [material]
            addChildNode(SCNNode(geometry: core))
            for side: Float in [-1, 1] {
                let wing = SCNBox(width: 1.15, height: 0.08, length: 0.36, chamferRadius: 0.08)
                wing.materials = [material]
                let node = SCNNode(geometry: wing)
                node.position.x = side * 0.65
                addChildNode(node)
            }

        case .laser:
            safeLaneY = position.y
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(red: 0.93, green: 0.34, blue: 0.35, alpha: 0.72)
            material.emission.contents = UIColor(red: 0.88, green: 0.18, blue: 0.24, alpha: 1)
            material.blendMode = .add
            for y: Float in [-2.5, 2.5] {
                let beam = SCNBox(width: 8.6, height: 3.1, length: 0.16, chamferRadius: 0.08)
                beam.materials = [material]
                let node = SCNNode(geometry: beam)
                node.position.y = y
                addChildNode(node)
            }

        case .pickup:
            let core = SCNPyramid(width: 0.72, height: 0.92, length: 0.72)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = palette.glow
            material.emission.contents = palette.glow
            core.materials = [material]
            addChildNode(SCNNode(geometry: core))
            let orbit = SCNTorus(ringRadius: 0.65, pipeRadius: 0.018)
            orbit.materials = [material]
            let orbitNode = SCNNode(geometry: orbit)
            orbitNode.eulerAngles.x = 0.7
            addChildNode(orbitNode)
        }
    }

    private static func asteroidGeometry(radius: CGFloat, seed: Int) -> SCNGeometry {
        let latitudes = 10
        let longitudes = 14
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []

        for lat in 0...latitudes {
            let v = Float(lat) / Float(latitudes)
            let phi = Float.pi * v
            for lon in 0...longitudes {
                let u = Float(lon) / Float(longitudes)
                let theta = 2 * Float.pi * u
                let noise = 1 + 0.13 * sin(Float(lat * 17 + lon * 11 + seed) * 1.73) + 0.07 * cos(Float(lat * 7 - lon * 13 + seed) * 0.91)
                let r = Float(radius) * noise
                let x = r * sin(phi) * cos(theta)
                let y = r * cos(phi)
                let z = r * sin(phi) * sin(theta)
                vertices.append(SCNVector3(x, y, z))
                let length = max(sqrt(x * x + y * y + z * z), 0.001)
                normals.append(SCNVector3(x / length, y / length, z / length))
            }
        }

        let stride = longitudes + 1
        for lat in 0..<latitudes {
            for lon in 0..<longitudes {
                let a = Int32(lat * stride + lon)
                let b = Int32((lat + 1) * stride + lon)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }

        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }
}
