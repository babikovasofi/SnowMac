import CoreGraphics
import Foundation

enum SnowBodyKind: Equatable {
    case ball
    case brick
    case snowman

    var size: CGSize {
        switch self {
        case .ball: CGSize(width: 26, height: 26)
        case .brick: CGSize(width: 46, height: 22)
        case .snowman: CGSize(width: 42, height: 82)
        }
    }
}

struct SnowBody: Equatable, Identifiable {
    let id: Int
    let kind: SnowBodyKind
    var center: CGPoint
    var velocity: CGVector = .zero
    var rolledDiameter: CGFloat?

    var size: CGSize {
        if let rolledDiameter { return CGSize(width: rolledDiameter, height: rolledDiameter) }
        return kind.size
    }
}

struct SnowGameFrame: Equatable {
    let bodies: [SnowBody]
    let plow: CGPoint?
    var plowLoad: CGFloat = 0
}

struct SnowGame {
    private static let maximumBodies = 48
    private let brickFromLeft: Bool
    private(set) var bodies: [SnowBody] = []
    private var nextID = 0
    private var dragID: Int?
    private var plowX: CGFloat?
    private var clearsDock = false
    private var plowPoint: CGPoint?
    private var plowLoad: CGFloat = 0

    init(seed: UInt64) {
        brickFromLeft = seed.isMultiple(of: 2)
    }

    var frame: SnowGameFrame {
        SnowGameFrame(bodies: bodies, plow: plowPoint, plowLoad: plowLoad)
    }

    var canSpawn: Bool { bodies.count < Self.maximumBodies }
    var heldBody: SnowBody? { bodies.first { $0.id == dragID } }

    mutating func spawn(_ kind: SnowBodyKind, at point: CGPoint, width: CGFloat) {
        guard canSpawn, point.x.isFinite, point.y.isFinite, width > 0 else { return }
        let center = CGPoint(x: clampX(point.x, width: width, radius: kind.size.width / 2),
                             y: max(point.y, kind.size.height / 2))
        bodies.append(SnowBody(id: nextID, kind: kind, center: center))
        nextID += 1
    }

    func brickSpawnX(width: CGFloat) -> CGFloat {
        let anchor = max(32, width * 0.16)
        let lanes = [CGFloat(0), -50, 50, -100, 100]
        return lanes.lazy.map { offset in
            self.brickFromLeft ? anchor + offset : width - anchor - offset
        }.first { x in
            x > 24 && x < width - 24 &&
                !self.bodies.contains { $0.kind == .brick && abs($0.center.x - x) < 45 && $0.center.y < 80 }
        } ?? (brickFromLeft ? anchor : width - anchor)
    }

    mutating func beginDrag(id: Int) {
        guard let index = bodies.firstIndex(where: { $0.id == id }) else { return }
        dragID = id
        bodies[index].velocity = .zero
    }

    mutating func beginRoll(at point: CGPoint, width: CGFloat) {
        guard canSpawn, dragID == nil else { return }
        let diameter: CGFloat = 12
        let center = CGPoint(x: clampX(point.x, width: width, radius: diameter / 2),
                             y: point.y + diameter / 2)
        bodies.append(SnowBody(id: nextID, kind: .ball, center: center, rolledDiameter: diameter))
        dragID = nextID
        nextID += 1
    }

    mutating func gather(_ amount: CGFloat) {
        guard let index = bodies.firstIndex(where: { $0.id == dragID }),
              let diameter = bodies[index].rolledDiameter else { return }
        bodies[index].rolledDiameter = min(52, sqrt(diameter * diameter + amount * 14))
    }

    mutating func drag(to point: CGPoint, elapsed: TimeInterval, size: CGSize) {
        guard let index = bodies.firstIndex(where: { $0.id == dragID }),
              point.x.isFinite, point.y.isFinite, elapsed.isFinite else { return }
        let body = bodies[index]
        let center = CGPoint(
            x: clampX(point.x, width: size.width, radius: body.size.width / 2),
            y: min(size.height, max(body.size.height / 2, point.y))
        )
        let dt = max(1.0 / 120, min(elapsed, 0.20))
        bodies[index].velocity = CGVector(
            dx: min(950, max(-950, (center.x - body.center.x) / dt)),
            dy: min(950, max(-950, (center.y - body.center.y) / dt))
        )
        bodies[index].center = center
    }

    mutating func endDrag() {
        dragID = nil
    }

    mutating func cancelInteraction() {
        if let index = bodies.firstIndex(where: { $0.id == dragID }) {
            bodies[index].velocity = .zero
        }
        dragID = nil
        plowX = nil
        plowPoint = nil
        plowLoad = 0
    }

    mutating func startPlow(clearsDock: Bool, width: CGFloat) {
        let entrance = width + 38
        plowX = entrance
        plowPoint = CGPoint(x: entrance, y: 12)
        plowLoad = 0
        self.clearsDock = clearsDock
    }

    mutating func advancePlow(dt: CGFloat, width: CGFloat, floor: (CGFloat) -> CGFloat) -> (x: CGFloat, clearsDock: Bool)? {
        guard let x = plowX else { return nil }
        let next = x - 150 * dt
        guard next > -48 else {
            plowX = nil
            plowPoint = nil
            plowLoad = 0
            return nil
        }
        plowX = next
        plowLoad = max(0, plowLoad - dt * 0.16)
        let wheelX = min(max(0, next + 23), max(0, width - 1))
        plowPoint = CGPoint(x: next, y: floor(wheelX) + 13)
        return (next - 27, clearsDock)
    }

    mutating func addPlowLoad(_ amount: CGFloat) {
        plowLoad = min(1, plowLoad + amount / 350)
    }

    mutating func advance(dt: CGFloat, size: CGSize, surface: (CGFloat, CGFloat) -> CGFloat) -> [CGPoint] {
        guard !bodies.isEmpty else { return [] }
        let previous = bodies
        let bottomFirst = bodies.indices.sorted { bodies[$0].center.y < bodies[$1].center.y }
        var broken: Set<Int> = []
        var debris: [CGPoint] = []
        for index in bottomFirst where bodies[index].id != dragID {
            if let impact = move(index, dt: dt, size: size, surface: surface) {
                broken.insert(index)
                debris.append(impact)
            }
        }

        for first in bodies.indices {
            for second in (first + 1)..<bodies.count where !broken.contains(second) {
                if broken.contains(first) { break }
                if breakOnImpact(first, second, previous: previous, dt: dt) {
                    broken.insert(first)
                    broken.insert(second)
                    debris.append(bodies[first].center)
                } else {
                    separateHorizontalContact(first, second, width: size.width)
                }
            }
        }
        bodies = bodies.enumerated().filter { !broken.contains($0.offset) }.map(\.element)
        if let dragID, !bodies.contains(where: { $0.id == dragID }) { self.dragID = nil }
        combineSnowman(surface: surface, width: size.width)
        return debris
    }

    private mutating func move(_ index: Int, dt: CGFloat, size: CGSize,
                               surface: (CGFloat, CGFloat) -> CGFloat) -> CGPoint? {
        let body = bodies[index]
        let radius = body.size.height / 2
        let oldBottom = body.center.y - radius
        var velocity = body.velocity
        velocity.dy = max(-900, velocity.dy - 680 * dt)
        let nextX = clampX(body.center.x + velocity.dx * dt, width: size.width, radius: body.size.width / 2)
        let nextY = body.center.y + velocity.dy * dt
        if nextX != body.center.x + velocity.dx * dt { velocity.dx *= -0.28 }
        if nextY > size.height { velocity.dy = min(0, velocity.dy) }

        let terrain = surface(nextX, oldBottom)
        let contact = highestSupport(for: body, x: nextX, oldBottom: oldBottom, terrain: terrain)
        let grounded = velocity.dy <= 0 && nextY - radius <= contact
        if grounded && contact == terrain && body.kind == .ball
            && (velocity.dy < -310 || abs(velocity.dx) > 530) {
            return CGPoint(x: nextX, y: contact + 3)
        }
        if grounded {
            velocity.dy = 0
            velocity.dx *= max(0, 1 - 9 * dt)
        }
        bodies[index].center = CGPoint(x: nextX, y: grounded ? contact + radius : min(size.height, nextY))
        bodies[index].velocity = velocity
        return nil
    }

    private func highestSupport(for body: SnowBody, x: CGFloat, oldBottom: CGFloat, terrain: CGFloat) -> CGFloat {
        var height = terrain
        for support in bodies where support.id != body.id && support.id != dragID {
            let top = support.center.y + support.size.height / 2
            let horizontalReach = body.kind == .ball && support.kind == .ball
                ? 10 : (body.size.width + support.size.width) / 2 - 3
            if top <= oldBottom + 2 && abs(support.center.x - x) < horizontalReach {
                height = max(height, top)
            }
        }
        return height
    }

    private mutating func separateHorizontalContact(_ first: Int, _ second: Int, width: CGFloat) {
        let firstBody = bodies[first]
        let secondBody = bodies[second]
        guard firstBody.id != dragID, secondBody.id != dragID else { return }
        let dx = firstBody.center.x - secondBody.center.x
        let dy = firstBody.center.y - secondBody.center.y
        let horizontalOverlap = (firstBody.size.width + secondBody.size.width) / 2 - abs(dx)
        let verticalOverlap = (firstBody.size.height + secondBody.size.height) / 2 - abs(dy)
        guard horizontalOverlap > 0, verticalOverlap > horizontalOverlap else { return }
        let direction: CGFloat = dx < 0 ? -1 : 1
        let requestedFirst = firstBody.center.x + direction * horizontalOverlap / 2
        let firstX = clampX(requestedFirst, width: width, radius: firstBody.size.width / 2)
        let remaining = horizontalOverlap - abs(firstX - firstBody.center.x)
        let secondX = clampX(secondBody.center.x - direction * remaining, width: width,
                             radius: secondBody.size.width / 2)
        bodies[first].center.x = firstX
        bodies[second].center.x = secondX
        if (firstBody.velocity.dx - secondBody.velocity.dx) * direction < 0 {
            bodies[first].velocity.dx = secondBody.velocity.dx * 0.5
            bodies[second].velocity.dx = firstBody.velocity.dx * 0.5
        }
    }

    private func breakOnImpact(_ first: Int, _ second: Int, previous: [SnowBody], dt: CGFloat) -> Bool {
        let firstBody = bodies[first]
        let secondBody = bodies[second]
        guard firstBody.id != dragID, secondBody.id != dragID,
              firstBody.kind == .ball || secondBody.kind == .ball,
              firstBody.kind != .snowman, secondBody.kind != .snowman else { return false }
        let delta = CGVector(dx: previous[first].velocity.dx - previous[second].velocity.dx,
                             dy: previous[first].velocity.dy - previous[second].velocity.dy)
        guard hypot(delta.dx, delta.dy) >= 460 else { return false }
        let xReach = (firstBody.size.width + secondBody.size.width) / 2
        let yReach = (firstBody.size.height + secondBody.size.height) / 2
        let step = CGVector(dx: firstBody.center.x - previous[first].center.x
                            - secondBody.center.x + previous[second].center.x,
                            dy: firstBody.center.y - previous[first].center.y
                            - secondBody.center.y + previous[second].center.y)
        let start = CGVector(dx: previous[first].center.x - previous[second].center.x,
                             dy: previous[first].center.y - previous[second].center.y)
        guard start.dx * delta.dx + start.dy * delta.dy < 0 else { return false }
        let travelSquared = step.dx * step.dx + step.dy * step.dy
        let closest = travelSquared > 0
            ? max(0, min(1, -(start.dx * step.dx + start.dy * step.dy) / travelSquared)) : 0
        let xDistance = abs(start.dx + step.dx * closest)
        let yDistance = abs(start.dy + step.dy * closest)
        return xDistance <= xReach + 1 && yDistance <= yReach + 680 * dt * dt + 1
    }

    private mutating func combineSnowman(surface: (CGFloat, CGFloat) -> CGFloat, width: CGFloat) {
        let balls = bodies.filter {
            $0.kind == .ball && $0.id != dragID && hypot($0.velocity.dx, $0.velocity.dy) < 12
        }.sorted { $0.center.y < $1.center.y }
        guard balls.count >= 3 else { return }

        for lower in balls {
            let bottom = lower.center.y - lower.size.height / 2
            let support = surface(lower.center.x, bottom)
            guard bottom <= support + 2 else { continue }
            guard let middle = ballAbove(lower, among: balls),
                  let upper = ballAbove(middle, among: balls) else { continue }
            let ids = Set([lower.id, middle.id, upper.id])
            bodies.removeAll { ids.contains($0.id) }
            let point = CGPoint(x: lower.center.x, y: support + SnowBodyKind.snowman.size.height / 2)
            spawn(.snowman, at: point, width: width)
            return
        }
    }

    private func ballAbove(_ lower: SnowBody, among balls: [SnowBody]) -> SnowBody? {
        balls.first {
            abs($0.center.x - lower.center.x) < 9 &&
                abs($0.center.y - lower.center.y - (lower.size.height + $0.size.height) / 2) < 3
        }
    }

    private func clampX(_ x: CGFloat, width: CGFloat, radius: CGFloat) -> CGFloat {
        let inset = min(radius, width / 2)
        return min(max(inset, x), width - inset)
    }
}
