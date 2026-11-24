import XCTest
@testable import SnowMac

final class SnowGameTests: XCTestCase {
    private let size = CGSize(width: 420, height: 300)
    private let step = 1.0 / 60

    func testBallStopsOnExactGroundContact() throws {
        var game = SnowGame(seed: 2)
        game.spawn(.ball, at: CGPoint(x: 100, y: 55.5), width: size.width)
        _ = game.advance(dt: 0.25, size: size, surface: { _, _ in 0 })
        let body = try XCTUnwrap(game.frame.bodies.first)
        XCTAssertEqual(body.center.y, 13)
        XCTAssertEqual(body.velocity.dy, 0)
    }

    func testBallWithZeroVerticalSpeedRestsOnRaisedSnow() throws {
        var game = SnowGame(seed: 2)
        game.spawn(.ball, at: CGPoint(x: 100, y: 13), width: size.width)
        let id = try XCTUnwrap(game.frame.bodies.first?.id)
        game.beginDrag(id: id)
        game.drag(to: CGPoint(x: 100, y: 23.625), elapsed: 0.125, size: size)
        game.endDrag()
        _ = game.advance(dt: 0.125, size: size, surface: { _, _ in 20 })
        XCTAssertEqual(game.frame.bodies.first?.center.y, 33)
    }

    func testThrownBallMovesByVelocityTimesElapsedTime() throws {
        var game = SnowGame(seed: 2)
        game.spawn(.ball, at: CGPoint(x: 160, y: 100), width: size.width)
        let id = try XCTUnwrap(game.frame.bodies.first?.id)
        game.beginDrag(id: id)
        game.drag(to: CGPoint(x: 170, y: 100), elapsed: 0.125, size: size)
        game.endDrag()
        _ = game.advance(dt: 0.125, size: size, surface: { _, _ in 0 })
        XCTAssertEqual(game.frame.bodies.first?.center.x, 180)
    }

    func testThreeSettledBallsCraftOneSnowman() {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        for height in [13, 39, 65] {
            world.spawn(.ball, at: CGPoint(x: 180, y: height))
        }
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertEqual(world.gameFrame.bodies.map(\.kind), [.snowman])
    }

    func testStackOfBricksDoesNotCraftASnowman() {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        for height in [11, 33, 55] {
            world.spawn(.brick, at: CGPoint(x: 180, y: height))
        }
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertEqual(world.gameFrame.bodies.map(\.kind), [.brick, .brick, .brick])
    }

    func testHeldBallDoesNotCraftUntilReleased() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        for height in [13, 39, 65] {
            world.spawn(.ball, at: CGPoint(x: 180, y: height))
        }
        let top = try XCTUnwrap(world.gameFrame.bodies.last)
        world.beginDrag(id: top.id)
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertEqual(world.gameFrame.bodies.map(\.kind), [.ball, .ball, .ball])
        world.endDrag()
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertEqual(world.gameFrame.bodies.map(\.kind), [.snowman])
    }

    func testDragClampsTheSnowballToTheLowerLeftCorner() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.ball, at: CGPoint(x: 180, y: 50))
        let ball = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: ball.id)
        world.drag(to: CGPoint(x: -70, y: -40), elapsed: 0.2)
        XCTAssertEqual(world.gameFrame.bodies.first?.center, CGPoint(x: 13, y: 13))
    }

    func testFastSnowballBreaksASnowBrick() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.ball, at: CGPoint(x: 130, y: 75))
        world.spawn(.brick, at: CGPoint(x: 230, y: 75))
        let ball = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: ball.id)
        world.drag(to: CGPoint(x: 185, y: 75), elapsed: 0.02)
        world.endDrag()
        for _ in 0..<5 { world.advance(elapsed: step, intensity: 0, locked: false) }
        XCTAssertTrue(world.gameFrame.bodies.isEmpty)
        XCTAssertFalse(world.frame.flakes.isEmpty)
    }

    func testHardThrowBreaksBothBallsAndProducesDebris() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.ball, at: CGPoint(x: 160, y: 75))
        world.spawn(.ball, at: CGPoint(x: 220, y: 75))
        let ball = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: ball.id)
        world.drag(to: CGPoint(x: 190, y: 75), elapsed: 0.02)
        world.endDrag()
        for _ in 0..<5 { world.advance(elapsed: step, intensity: 0, locked: false) }
        XCTAssertTrue(world.gameFrame.bodies.isEmpty)
        XCTAssertFalse(world.frame.flakes.isEmpty)
    }

    func testGentleCollisionKeepsBothBalls() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.ball, at: CGPoint(x: 160, y: 75))
        world.spawn(.ball, at: CGPoint(x: 220, y: 75))
        let ball = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: ball.id)
        world.drag(to: CGPoint(x: 190, y: 75), elapsed: 0.12)
        world.endDrag()
        for _ in 0..<10 { world.advance(elapsed: step, intensity: 0, locked: false) }
        let balls = world.gameFrame.bodies
        XCTAssertEqual(balls.count, 2)
        let first = try XCTUnwrap(balls.first)
        let second = try XCTUnwrap(balls.last)
        XCTAssertGreaterThanOrEqual(abs(first.center.x - second.center.x), 25.9)
    }

    func testBrickSpawnRemainsOnSameSideAfterFirstBrickMoves() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.brick)
        let first = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: first.id)
        let movedX: CGFloat = first.center.x < size.width / 2 ? size.width - 90 : 90
        world.drag(to: CGPoint(x: movedX, y: 100), elapsed: 0.2)
        world.endDrag()
        world.spawn(.brick)
        let new = try XCTUnwrap(world.gameFrame.bodies.last)
        XCTAssertEqual(new.center.x, first.center.x)
        XCTAssertNotEqual(new.id, first.id)
    }

    func testBrickFallsOnceItsSupportIsMoved() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.brick, at: CGPoint(x: 180, y: 11))
        world.spawn(.brick, at: CGPoint(x: 180, y: 33))
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertEqual(world.gameFrame.bodies.last?.center.y, 33)
        let base = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: base.id)
        world.drag(to: CGPoint(x: 300, y: 11), elapsed: 0.2)
        world.endDrag()
        for _ in 0..<25 { world.advance(elapsed: step, intensity: 0, locked: false) }
        XCTAssertEqual(world.gameFrame.bodies.last?.center.y, 11)
    }

    func testShovelClearsProfileAndPilesSnowAhead() throws {
        var world = try settledWorld()
        let before = try XCTUnwrap(world.frame.drifts.first).heights
        world.shovel(at: CGPoint(x: 135, y: 0), direction: 1)
        let after = try XCTUnwrap(world.frame.drifts.first).heights
        XCTAssertTrue(zip(before, after).contains { $0 > 0 && $1 == 0 })
        XCTAssertTrue(zip(before, after).contains { $1 > $0 })
    }

    func testPlowClearsGroundAndOptionallyClearsDock() throws {
        var floorOnly = SnowWorld(size: size)
        floorOnly.update(size: size, supports: [
            SnowSupport(id: "dock", minX: 155, maxX: 270, y: 55, velocityX: 0)
        ])
        for _ in 0..<(60 * 40) { floorOnly.advance(elapsed: step, intensity: 1, locked: false) }
        let beforeFloor = try XCTUnwrap(floorOnly.frame.drifts.first).heights
        let beforeDock = try XCTUnwrap(floorOnly.frame.drifts.first { $0.id == "dock" }).heights
        var dockAndFloor = floorOnly

        floorOnly.startPlow(clearsDock: false)
        dockAndFloor.startPlow(clearsDock: true)
        for _ in 0..<(60 * 2) {
            floorOnly.advance(elapsed: step, intensity: 0, locked: false)
            dockAndFloor.advance(elapsed: step, intensity: 0, locked: false)
        }
        let ground = try XCTUnwrap(dockAndFloor.frame.drifts.first).heights
        let untouchedDock = try XCTUnwrap(floorOnly.frame.drifts.first { $0.id == "dock" }).heights
        let cleanedDock = try XCTUnwrap(dockAndFloor.frame.drifts.first { $0.id == "dock" }).heights
        XCTAssertLessThan(ground.reduce(0, +), beforeFloor.reduce(0, +))
        XCTAssertGreaterThanOrEqual(untouchedDock.reduce(0, +), beforeDock.reduce(0, +))
        XCTAssertLessThan(cleanedDock.reduce(0, +), untouchedDock.reduce(0, +))
    }

    func testSnowmenSpawnAtDistinctUnoccupiedPositions() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.snowman)
        world.spawn(.snowman)
        XCTAssertEqual(world.gameFrame.bodies.count, 2)
        let first = try XCTUnwrap(world.gameFrame.bodies.first)
        let second = try XCTUnwrap(world.gameFrame.bodies.last)
        XCTAssertGreaterThan(abs(first.center.x - second.center.x), first.size.width)
    }

    func testLockCancelsPlowAndDragWithoutDeletingBodies() throws {
        var world = try settledWorld()
        world.spawn(.snowman, at: CGPoint(x: 110, y: 100))
        let snowman = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: snowman.id)
        world.drag(to: CGPoint(x: 120, y: 105), elapsed: 0.08)
        let position = world.gameFrame.bodies.first?.center
        world.startPlow()
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertNotNil(world.gameFrame.plow)
        world.advance(elapsed: step, intensity: 0, locked: true)
        XCTAssertNil(world.gameFrame.plow)
        world.drag(to: CGPoint(x: 300, y: 250), elapsed: 0.01)
        world.shovel(at: CGPoint(x: 120, y: 0), direction: -1)
        XCTAssertEqual(world.gameFrame.bodies.first?.center, position)
        XCTAssertEqual(world.gameFrame.bodies.first?.velocity, .zero)
    }

    func testCollectUsesGroundSnowAndProducesDraggableBall() throws {
        var world = try settledWorld()
        let ground = try XCTUnwrap(world.frame.drifts.first)
        let tallest = try XCTUnwrap(ground.heights.indices.max { ground.heights[$0] < ground.heights[$1] })
        let x = ground.firstColumnX + (CGFloat(tallest) + 0.5) * ground.columnWidth
        world.collect(at: CGPoint(x: x, y: 0))
        XCTAssertEqual(world.gameFrame.bodies.last?.kind, .ball)
        XCTAssertEqual(world.frame.drifts.first?.heights[tallest], 0)
    }

    func testRollingGrowsOneBallAndRemovesSnowAlongThePath() throws {
        var world = try settledWorld()
        let before = try XCTUnwrap(world.frame.drifts.first).heights.reduce(0, +)
        let start = CGPoint(x: 90, y: 12)
        XCTAssertTrue(world.canRollSnow(at: start))
        XCTAssertTrue(world.beginRoll(at: start))
        let seed = try XCTUnwrap(world.gameFrame.bodies.first)
        world.roll(to: CGPoint(x: 181, y: 12), elapsed: 0.2)
        let grown = try XCTUnwrap(world.gameFrame.bodies.first)
        XCTAssertEqual(world.gameFrame.bodies.count, 1)
        XCTAssertEqual(seed.id, grown.id)
        XCTAssertGreaterThan(grown.size.width, seed.size.width)
        XCTAssertLessThan(try XCTUnwrap(world.frame.drifts.first).heights.reduce(0, +), before)
        XCTAssertTrue(world.frame.flakes.contains { $0.sourceSupportID == "debris" })

        world.advance(elapsed: step, intensity: 0, locked: true)
        XCTAssertFalse(world.beginRoll(at: start))
        let heldPosition = try XCTUnwrap(world.gameFrame.bodies.first).center
        world.roll(to: CGPoint(x: 240, y: 12), elapsed: 0.1)
        XCTAssertEqual(world.gameFrame.bodies.first?.center, heldPosition)
    }

    func testRollingScoopsDockAndWindowSnow() throws {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [
            SnowSupport(id: "dock", minX: 80, maxX: 200, y: 58, velocityX: 0),
            SnowSupport(id: "window", minX: 220, maxX: 395, y: 150, velocityX: 0)
        ])
        for _ in 0..<(60 * 46) { world.advance(elapsed: step, intensity: 1, locked: false) }
        for (id, top) in [("dock", CGFloat(58)), ("window", CGFloat(150))] {
            let before = try XCTUnwrap(world.frame.drifts.first { $0.id == id })
            let column = try XCTUnwrap(before.heights.indices.max { before.heights[$0] < before.heights[$1] })
            let x = before.firstColumnX + (CGFloat(column) + 0.5) * before.columnWidth
            XCTAssertTrue(world.beginRoll(at: CGPoint(x: x, y: top + before.heights[column])))
            world.endDrag()
            let after = try XCTUnwrap(world.frame.drifts.first { $0.id == id })
            XCTAssertLessThan(after.heights[column], before.heights[column])
        }
    }

    func testThreeBallsCraftASnowmanStandingOnTheDock() throws {
        var world = SnowWorld(size: size)
        let dockTop: CGFloat = 58
        world.update(size: size, supports: [
            SnowSupport(id: "dock", minX: 65, maxX: 310, y: dockTop, velocityX: 0)
        ])
        world.advance(elapsed: step, intensity: 0, locked: false)
        for offset in [13, 39, 65] {
            world.spawn(.ball, at: CGPoint(x: 180, y: dockTop + CGFloat(offset)))
        }
        world.advance(elapsed: step, intensity: 0, locked: false)
        let snowman = try XCTUnwrap(world.gameFrame.bodies.first)
        XCTAssertEqual(world.gameFrame.bodies.count, 1)
        XCTAssertEqual(snowman.kind, .snowman)
        XCTAssertEqual(snowman.center.y - snowman.size.height / 2, dockTop)
    }

    func testHardLandingScattersPowderAcrossTheGround() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.ball, at: CGPoint(x: 180, y: 175))
        let ball = try XCTUnwrap(world.gameFrame.bodies.first)
        world.beginDrag(id: ball.id)
        world.drag(to: CGPoint(x: 180, y: 28), elapsed: 0.05)
        world.endDrag()
        for _ in 0..<6 { world.advance(elapsed: step, intensity: 0, locked: false) }
        XCTAssertTrue(world.gameFrame.bodies.isEmpty)
        let powder = world.frame.flakes.filter { $0.sourceSupportID == "debris" }
        XCTAssertGreaterThanOrEqual(powder.count, 20)
        XCTAssertTrue(powder.contains { $0.velocity.dx < -20 })
        XCTAssertTrue(powder.contains { $0.velocity.dx > 20 })
    }

    func testFastDownwardImpactShattersBothStackedBalls() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step, intensity: 0, locked: false)
        world.spawn(.ball, at: CGPoint(x: 180, y: 13))
        world.spawn(.ball, at: CGPoint(x: 180, y: 175))
        let ball = try XCTUnwrap(world.gameFrame.bodies.last)
        world.beginDrag(id: ball.id)
        world.drag(to: CGPoint(x: 180, y: 48), elapsed: 0.05)
        world.endDrag()
        for _ in 0..<6 { world.advance(elapsed: step, intensity: 0, locked: false) }
        XCTAssertTrue(world.gameFrame.bodies.isEmpty)
        XCTAssertTrue(world.frame.flakes.contains { $0.sourceSupportID == "debris" })
    }

    func testPlowStartsOnTheRightAndBuildsLoadWhileSweepingLeft() throws {
        var world = try settledWorld()
        world.startPlow()
        XCTAssertGreaterThan(try XCTUnwrap(world.gameFrame.plow).x, size.width)
        for _ in 0..<60 { world.advance(elapsed: step, intensity: 0, locked: false) }
        XCTAssertLessThan(try XCTUnwrap(world.gameFrame.plow).x, size.width - 80)
        XCTAssertGreaterThan(world.gameFrame.plowLoad, 0)
    }

    private func settledWorld() throws -> SnowWorld {
        var world = SnowWorld(size: size)
        for _ in 0..<(60 * 40) { world.advance(elapsed: step, intensity: 1, locked: false) }
        let ground = try XCTUnwrap(world.frame.drifts.first)
        XCTAssertGreaterThan(ground.heights.max() ?? 0, 8)
        return world
    }
}
