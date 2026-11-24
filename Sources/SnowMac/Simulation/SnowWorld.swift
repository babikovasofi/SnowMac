import CoreGraphics
import Foundation

struct SnowWorld {
    private static let step = 1.0 / 60
    private static let maximumSteps = 5
    private static let stationarySpeed: CGFloat = 18
    private static let gravity: CGFloat = 82

    private var size: CGSize
    private var floor: SnowSurface
    private var game: SnowGame
    private var gameEnabled = false
    private var rollPoint: CGPoint?
    private var supports: [SnowSurface] = []
    private var flakes: [SnowFlake] = []
    private var time: CGFloat = 0
    private var accumulator: TimeInterval = 0
    private var spawnCredit: CGFloat = 0
    private var randomState: UInt64
    let particleLimit: Int

    init(size: CGSize, seed: UInt64 = 313, particleLimit: Int = 1_600) {
        self.size = size
        self.floor = SnowSurface(Self.floorSupport(for: size))
        self.game = SnowGame(seed: seed)
        self.randomState = seed
        self.particleLimit = max(0, particleLimit)
    }

    var frame: SnowFrame {
        SnowFrame(size: size, flakes: flakes, drifts: floor.drifts + supports.flatMap(\.drifts))
    }

    var gameFrame: SnowGameFrame { game.frame }

    mutating func spawn(_ kind: SnowBodyKind, at point: CGPoint? = nil) {
        guard gameEnabled, game.canSpawn, size.width > 0 else { return }
        if let point {
            game.spawn(kind, at: point, width: size.width)
            return
        }
        let x: CGFloat
        if kind == .brick {
            x = game.brickSpawnX(width: size.width)
        } else {
            guard let position = freeSpawnX(for: kind) else { return }
            x = position
        }
        game.spawn(kind, at: CGPoint(x: x, y: groundHeight(at: x) + kind.size.height / 2 + 10),
                   width: size.width)
    }

    private mutating func freeSpawnX(for kind: SnowBodyKind) -> CGFloat? {
        let inset = min(48, size.width / 2)
        let span = inset...(size.width - inset)
        for _ in 0..<12 {
            let x = random(in: span)
            let top = groundHeight(at: x) + kind.size.height + 10
            let occupied = game.bodies.contains { body in
                body.center.y - body.size.height / 2 < top &&
                    abs(body.center.x - x) < (kind.size.width + body.size.width) / 2 + 8
            }
            if !occupied { return x }
        }
        return nil
    }

    mutating func beginDrag(id: Int) {
        if gameEnabled { game.beginDrag(id: id) }
    }

    mutating func drag(to point: CGPoint, elapsed: TimeInterval) {
        if gameEnabled { game.drag(to: point, elapsed: elapsed, size: size) }
    }

    mutating func endDrag() {
        rollPoint = nil
        game.endDrag()
    }

    mutating func cancelInteraction() {
        gameEnabled = false
        rollPoint = nil
        game.cancelInteraction()
    }

    func canRollSnow(at point: CGPoint) -> Bool {
        gameEnabled && game.canSpawn && rollSurface(at: point) != nil
    }

    mutating func beginRoll(at point: CGPoint) -> Bool {
        guard canRollSnow(at: point), game.heldBody == nil,
              let surface = rollSurface(at: point) else { return false }
        game.beginRoll(at: CGPoint(x: point.x, y: surface.top), width: size.width)
        rollPoint = point
        game.gather(gather(from: surface.index, at: point.x))
        return true
    }

    mutating func roll(to point: CGPoint, elapsed: TimeInterval) {
        guard gameEnabled, let previous = rollPoint, game.heldBody != nil,
              point.x.isFinite, point.y.isFinite else { return }
        let distance = hypot(point.x - previous.x, point.y - previous.y)
        guard distance >= 2 else { return }
        let steps = Int(min(32, max(1, ceil(distance / 9))))
        var gathered: CGFloat = 0
        if (game.heldBody?.size.width ?? 52) < 52 {
            for index in 1...steps {
                let progress = CGFloat(index) / CGFloat(steps)
                let sample = CGPoint(x: previous.x + (point.x - previous.x) * progress,
                                     y: previous.y + (point.y - previous.y) * progress)
                if let surface = rollSurface(at: sample) {
                    gathered += gather(from: surface.index, at: sample.x)
                }
            }
        }
        game.gather(gathered)
        rollPoint = point
        let radius = (game.heldBody?.size.height ?? 12) / 2
        let top = rollSurface(at: point, requiresSnow: false)?.top
        let center = CGPoint(x: point.x, y: top.map { $0 + radius } ?? point.y)
        game.drag(to: center, elapsed: elapsed, size: size)
        if gathered >= 1, let top {
            scatter(at: CGPoint(x: point.x, y: top + 2), count: 3,
                    drift: (point.x - previous.x).sign == .minus ? 25 : -25)
        }
    }

    // An index of nil represents the floor, whose visible snow is also sampled.
    private func rollSurface(at point: CGPoint, requiresSnow: Bool = true) -> (index: Int?, top: CGFloat)? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        for index in supports.indices {
            if let top = rollTop(for: supports[index], at: point, requiresSnow: requiresSnow) {
                return (index, top)
            }
        }
        return rollTop(for: floor, at: point, requiresSnow: requiresSnow).map { (nil, $0) }
    }

    private func rollTop(for surface: SnowSurface, at point: CGPoint, requiresSnow: Bool) -> CGFloat? {
        guard let column = surface.column(at: point.x) else { return nil }
        let snow = surface.heights[column]
        let top = surface.support.y + snow
        guard (!requiresSnow || snow >= 0.65), point.y >= surface.support.y - 5,
              point.y <= top + 28 else { return nil }
        return top
    }

    private mutating func gather(from index: Int?, at x: CGFloat) -> CGFloat {
        if let index { return supports[index].gather(at: x) }
        return floor.gather(at: x)
    }

    mutating func collect(at point: CGPoint) {
        guard gameEnabled, game.canSpawn, floor.column(at: point.x) != nil,
              point.y.isFinite, point.y >= -6, point.y <= groundHeight(at: point.x) + 30 else { return }
        guard groundHeight(at: point.x) >= 1 else { return }
        let collected = floor.sweep(at: point.x, radius: 15, direction: 1, leavesPile: false)
        guard collected > 0 else { return }
        spawn(.ball, at: CGPoint(x: point.x, y: max(point.y, groundHeight(at: point.x)) + 13))
    }

    mutating func shovel(at point: CGPoint, direction: CGFloat) {
        guard gameEnabled, point.y.isFinite, point.y >= -8, point.y < groundHeight(at: point.x) + 42 else { return }
        _ = floor.sweep(at: point.x, radius: 22, direction: direction)
    }

    mutating func startPlow(clearsDock: Bool = false) {
        if gameEnabled { game.startPlow(clearsDock: clearsDock, width: size.width) }
    }

    private func groundHeight(at x: CGFloat) -> CGFloat {
        guard let column = floor.column(at: x) else { return 0 }
        return floor.heights[column]
    }

    mutating func update(size: CGSize, supports observedSupports: [SnowSupport]) {
        if self.size != size {
            self.size = size
            floor.reshape(to: Self.floorSupport(for: size))
            flakes.removeAll { $0.position.x < -10 || $0.position.x > size.width + 10 }
        }
        let old = Dictionary(uniqueKeysWithValues: supports.map { ($0.support.id, $0) })
        var seen: Set<String> = []
        supports = observedSupports.compactMap { support in
            guard !support.id.isEmpty, support.minX.isFinite, support.maxX.isFinite,
                  support.y.isFinite, support.maxX > support.minX,
                  support.maxX > 0, support.minX < size.width,
                  support.y > 0, support.y < size.height,
                  support.visibleRanges.allSatisfy({
                      !$0.isEmpty && $0.lowerBound >= max(0, support.minX) &&
                          $0.upperBound <= min(size.width, support.maxX)
                  }),
                  seen.insert(support.id).inserted else { return nil }
            var surface = old[support.id] ?? SnowSurface(support)
            surface.reshape(to: support)
            return surface
        }
        supports.sort {
            if $0.support.y == $1.support.y { return $0.support.id < $1.support.id }
            return $0.support.y > $1.support.y
        }
    }

    mutating func advance(elapsed: TimeInterval, intensity: Double, locked: Bool, floorDepth: CGFloat = 40,
                          wind: CGFloat = 0, snowOnSupports: Bool = true, toolsEnabled: Bool = true) {
        let enablesGame = !locked && toolsEnabled
        if gameEnabled && !enablesGame { cancelInteraction() }
        gameEnabled = enablesGame
        guard elapsed.isFinite, elapsed > 0 else { return }
        let strength = intensity.isFinite ? CGFloat(min(1, max(0, intensity))) : 0
        if strength == 0 { spawnCredit = 0 }
        accumulator += min(elapsed, Self.step * Double(Self.maximumSteps))
        var steps = 0
        while accumulator + 1e-10 >= Self.step && steps < Self.maximumSteps {
            simulate(dt: Self.step, intensity: strength, locked: locked, floorDepth: floorDepth,
                     wind: wind.isFinite ? min(1, max(-1, wind)) : 0, snowOnSupports: snowOnSupports)
            accumulator = max(0, accumulator - Self.step)
            steps += 1
        }
    }

    mutating func resetClock() {
        accumulator = 0
    }

    private mutating func simulate(dt: CGFloat, intensity: CGFloat, locked: Bool, floorDepth: CGFloat,
                                   wind: CGFloat, snowOnSupports: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        time += dt
        let floorLimit = min(max(0, floorDepth), size.height * 0.3)
        floor.melt(dt: dt, rate: 3, downTo: floorLimit)
        if locked {
            floor.melt(dt: dt, rate: 0.16, downTo: min(2, floorLimit))
            for index in supports.indices {
                let rate: CGFloat = supports[index].support.id == "dock" ? 0.16 : 0.26
                supports[index].melt(dt: dt, rate: rate)
            }
        }
        if snowOnSupports {
            shedFromMovingSupports(dt: dt)
        } else {
            for index in supports.indices { supports[index].melt(dt: dt, rate: 4, downTo: 0) }
        }
        if gameEnabled { advanceGame(dt: dt) }
        let heightLimit: CGFloat = locked ? 6 : 24
        var survivors: [SnowFlake] = []
        survivors.reserveCapacity(flakes.count)
        for var flake in flakes {
            let previous = flake.position
            if flake.isDislodged {
                flake.velocity.dy = max(-210, flake.velocity.dy - Self.gravity * dt)
                flake.velocity.dx *= (1 - dt * 1.2)
            }
            let flutter = sin(time * 1.7 + flake.phase) * 18
            flake.position.x += (flake.velocity.dx + flutter + wind * 100) * dt
            flake.position.y += flake.velocity.dy * dt
            if flake.position.x < -14 || flake.position.x > size.width + 14 { continue }
            if land(flake, from: previous, limit: heightLimit, floorLimit: floorLimit, snowOnSupports: snowOnSupports) { continue }
            if flake.position.y > -10 { survivors.append(flake) }
        }
        flakes = survivors
        spawnCredit += min(250, max(24, size.width * 0.13)) * intensity * dt
        let count = Int(spawnCredit)
        spawnCredit -= CGFloat(count)
        guard count > 0 else { return }
        for _ in 0..<min(count, particleLimit - flakes.count) {
            let radius = random(in: 0.65...2.2)
            let position = CGPoint(x: random(in: 0...size.width), y: size.height + radius)
            let velocity = CGVector(dx: random(in: -12...19), dy: random(in: -138 ... -58))
            let phase = random(in: 0...(2 * .pi))
            flakes.append(SnowFlake(position: position, velocity: velocity,
                                    radius: radius, phase: phase, sourceSupportID: nil))
        }
    }

    private mutating func advanceGame(dt: CGFloat) {
        let surface = floor
        let elevated = supports
        let terrain: (CGFloat) -> CGFloat = { x in
            guard let column = surface.column(at: x) else { return 0 }
            return surface.heights[column]
        }
        let collisionSurface: (CGFloat, CGFloat) -> CGFloat = { x, previousBottom in
            var height = terrain(x)
            for support in elevated {
                guard let column = support.column(at: x) else { continue }
                let top = support.support.y + support.heights[column]
                if top <= previousBottom + 2 { height = max(height, top) }
            }
            return height
        }
        for point in game.advance(dt: dt, size: size, surface: collisionSurface) {
            scatter(at: point, count: 26, spread: 210)
        }
        guard let plow = game.advancePlow(dt: dt, width: size.width, floor: terrain) else { return }
        let removed = floor.sweep(at: plow.x, radius: 15, direction: -1)
        game.addPlowLoad(removed)
        if removed > 2 {
            scatter(at: CGPoint(x: plow.x, y: terrain(plow.x) + 4), count: 4, drift: -60)
        }
        if plow.clearsDock, let index = supports.firstIndex(where: { $0.support.id == "dock" }) {
            _ = supports[index].sweep(at: plow.x, radius: 15, direction: -1)
        }
    }

    private mutating func scatter(at point: CGPoint, count: Int, drift: CGFloat = 0, spread: CGFloat = 45) {
        for _ in 0..<min(count, particleLimit - flakes.count) {
            let velocity = CGVector(dx: drift + random(in: -spread...spread), dy: random(in: 35...150))
            let radius = random(in: 0.8...2.3)
            flakes.append(SnowFlake(position: point, velocity: velocity,
                                    radius: radius, phase: 0, sourceSupportID: "debris"))
        }
    }

    private mutating func land(_ flake: SnowFlake, from previous: CGPoint, limit: CGFloat,
                               floorLimit: CGFloat, snowOnSupports: Bool) -> Bool {
        guard flake.position.y < previous.y else { return false }
        for index in supports.indices where snowOnSupports {
            guard supports[index].support.id != flake.sourceSupportID else { continue }
            guard let column = supports[index].column(at: flake.position.x) else { continue }
            let top = supports[index].support.y + supports[index].heights[column]
            if previous.y >= top && flake.position.y <= top {
                let isDock = supports[index].support.id == "dock"
                supports[index].deposit(at: column, radius: flake.radius * (isDock ? 4 : 2),
                                        limit: isDock ? min(9, limit + 2) : limit)
                return true
            }
        }
        guard let column = floor.column(at: flake.position.x),
              flake.position.y <= floor.heights[column] else { return false }
        floor.deposit(at: column, radius: flake.radius * (3 + floorLimit / 10), limit: floorLimit)
        return true
    }

    private mutating func shedFromMovingSupports(dt: CGFloat) {
        for index in supports.indices {
            let support = supports[index].support
            let speed = hypot(support.velocityX, support.velocityY)
            guard speed.isFinite, speed > Self.stationarySpeed else { continue }
            let amountPerSecond = min(6, (speed - Self.stationarySpeed) / 90)
            for column in supports[index].heights.indices {
                let existing = supports[index].heights[column]
                guard existing > 0, let exposed = supports[index].exposedBounds(of: column) else { continue }
                let release = min(existing, existing * amountPerSecond * dt)
                supports[index].heights[column] -= release
                guard flakes.count < particleLimit, random(in: 0...1) < min(1, release * 1.7) else {
                    continue
                }
                let position = CGPoint(x: random(in: exposed.lowerBound...exposed.upperBound),
                                       y: support.y + existing + 1)
                let horizontal = min(240, max(-240, support.velocityX * 0.52))
                let vertical = min(35, max(-90, support.velocityY * 0.32))
                let velocity = CGVector(dx: horizontal + random(in: -19...19),
                                        dy: vertical + random(in: -35 ... -15))
                let radius = random(in: 0.85...2.4)
                let phase = random(in: 0...(2 * .pi))
                flakes.append(SnowFlake(position: position, velocity: velocity,
                                        radius: radius, phase: phase, sourceSupportID: support.id))
            }
        }
    }

    private mutating func random(in range: ClosedRange<CGFloat>) -> CGFloat {
        randomState = 2_862_933_555_777_941_757 &* randomState &+ 3_037_000_493
        let fraction = CGFloat(randomState >> 11) / 9_007_199_254_740_992
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    private static func floorSupport(for size: CGSize) -> SnowSupport {
        SnowSupport(id: "", minX: 0, maxX: max(0, size.width), y: 0, velocityX: 0)
    }
}
