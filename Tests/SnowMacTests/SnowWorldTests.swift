import XCTest
@testable import SnowMac

final class SnowWorldTests: XCTestCase {
    private let size = CGSize(width: 320, height: 240)
    private let step = 1.0 / 60

    private func support(
        velocityX: CGFloat = 0, velocityY: CGFloat = 0, offset: CGFloat = 0,
        visibleRanges: [Range<CGFloat>]? = nil
    ) -> SnowSupport {
        SnowSupport(id: "finder", minX: 80 + offset, maxX: 240 + offset, y: 135,
                    velocityX: velocityX, velocityY: velocityY, visibleRanges: visibleRanges)
    }

    private func fill(_ world: inout SnowWorld, seconds: Int = 12, locked: Bool = false) {
        for _ in 0..<(seconds * 60) {
            world.advance(elapsed: step, intensity: 1, locked: locked)
        }
    }

    func testDockKeepsVisibleSnowInLightSnowfall() throws {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [
            SnowSupport(id: "dock", minX: 55, maxX: 265, y: 40, velocityX: 0)
        ])
        for _ in 0..<(25 * 60) {
            world.advance(elapsed: step, intensity: 0.25, locked: true)
        }
        let dock = try XCTUnwrap(world.frame.drifts.first { $0.id == "dock" })
        XCTAssertGreaterThan(dock.heights.filter { $0 >= 2 }.count, dock.heights.count / 2)
        XCTAssertLessThanOrEqual(dock.heights.max() ?? .infinity, 8)
        fill(&world, seconds: 85, locked: true)
        let settledDock = try XCTUnwrap(world.frame.drifts.first { $0.id == "dock" })
        let highest = try XCTUnwrap(settledDock.heights.max())
        let lowest = try XCTUnwrap(settledDock.heights.min())
        XCTAssertGreaterThan(lowest, 0)
        XCTAssertGreaterThan(highest - lowest, 3)
        XCTAssertLessThanOrEqual(highest, 8)
    }

    func testSnowAccumulatesOnWindowAndFloor() {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [support()])
        fill(&world)

        XCTAssertTrue(world.frame.drifts.first(where: { $0.id == "finder" })?
            .heights.contains(where: { $0 > 0 }) == true)
        XCTAssertTrue(world.frame.drifts.first(where: { $0.id == nil })?
            .heights.contains(where: { $0 > 0 }) == true)
    }

    func testClosingOrReplacingWindowClearsItsSnow() {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [support()])
        fill(&world)

        world.update(size: size, supports: [])
        XCTAssertEqual(world.frame.drifts.compactMap(\.id), [])
        world.update(size: size, supports: [support()])
        XCTAssertTrue(world.frame.drifts.first(where: { $0.id == "finder" })?
            .heights.allSatisfy { $0 == 0 } == true)
    }

    func testOcclusionSplitsRenderingWithoutMovingOrLosingAccumulation() throws {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [support()])
        fill(&world)
        let before = try XCTUnwrap(world.frame.drifts.first { $0.id == "finder" })

        world.update(size: size, supports: [support(visibleRanges: [80..<120, 176..<240])])
        let segments = world.frame.drifts.filter { $0.id == "finder" }
        XCTAssertEqual(segments.map(\.left), [80, 176])
        XCTAssertEqual(segments.map(\.right), [120, 240])
        XCTAssertEqual(segments.first?.heights, Array(before.heights.prefix(5)))
        XCTAssertEqual(segments.last?.heights, Array(before.heights.suffix(8)))

        world.update(size: size, supports: [support(visibleRanges: [])])
        XCTAssertFalse(world.frame.drifts.contains { $0.id == "finder" })
        world.update(size: size, supports: [support()])
        XCTAssertEqual(world.frame.drifts.first { $0.id == "finder" }, before)
    }

    func testVisibleWindowSegmentCanBeginAtScreenEdge() throws {
        var world = SnowWorld(size: size)
        let spanningWindow = SnowSupport(id: "finder", minX: -64, maxX: 144, y: 135,
                                         velocityX: 0, visibleRanges: [0..<144])
        world.update(size: size, supports: [spanningWindow])
        fill(&world)
        let drift = try XCTUnwrap(world.frame.drifts.first { $0.id == "finder" })
        XCTAssertEqual(drift.left, 0)
        XCTAssertEqual(drift.right, 144)
        XCTAssertGreaterThan(drift.heights.reduce(0, +), 0)
    }

    func testResizeUpdatesFrameAndKeepsFloorSnowWithinNewBounds() throws {
        var world = SnowWorld(size: size)
        fill(&world)
        let originalFloor = try XCTUnwrap(world.frame.drifts.first)
        let resized = CGSize(width: 240, height: 200)

        world.update(size: resized, supports: [])

        let floor = try XCTUnwrap(world.frame.drifts.first)
        XCTAssertEqual(world.frame.size, resized)
        XCTAssertEqual(floor.right, resized.width)
        XCTAssertLessThan(floor.heights.count, originalFloor.heights.count)
        XCTAssertEqual(floor.heights, Array(originalFloor.heights.prefix(floor.heights.count)))
        XCTAssertTrue(world.frame.flakes.allSatisfy { $0.position.x <= resized.width + 10 })
    }

    func testSupportAtOrAboveDisplayTopDoesNotCreateDrift() {
        var world = SnowWorld(size: size)
        let inside = SnowSupport(id: "inside", minX: 0, maxX: 80,
                                 y: size.height - 1, velocityX: 0)
        let edge = SnowSupport(id: "edge", minX: 80, maxX: 160,
                               y: size.height, velocityX: 0)
        let outside = SnowSupport(id: "outside", minX: 160, maxX: 240,
                                  y: size.height + 1, velocityX: 0)

        world.update(size: size, supports: [edge, inside, outside])

        XCTAssertEqual(world.frame.drifts.compactMap(\.id), ["inside"])
    }

    func testFlakeStartingExactlyOnNewSupportLands() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step * 2, intensity: 1, locked: false)
        for _ in 0..<20 {
            world.advance(elapsed: step, intensity: 0, locked: false)
        }
        let height = try XCTUnwrap(world.frame.flakes.first?.position.y)
        let newSupport = SnowSupport(id: "finder", minX: 0, maxX: size.width,
                                     y: height, velocityX: 0)
        world.update(size: size, supports: [newSupport])
        world.advance(elapsed: step, intensity: 0, locked: false)
        XCTAssertTrue(world.frame.flakes.isEmpty)
        XCTAssertGreaterThan(mass(on: "finder", in: world.frame), 0)
    }

    func testFirstContactIsHighestSupportWhenOneStepCrossesTwoEdges() throws {
        var world = SnowWorld(size: size)
        world.advance(elapsed: step * 2, intensity: 1, locked: false)
        for _ in 0..<20 {
            world.advance(elapsed: step, intensity: 0, locked: false)
        }
        let flake = try XCTUnwrap(world.frame.flakes.first)
        let higher = SnowSupport(id: "top", minX: 0, maxX: size.width,
                                 y: flake.position.y, velocityX: 0)
        let lower = SnowSupport(id: "bottom", minX: 0, maxX: size.width,
                                y: flake.position.y + flake.velocity.dy * step * 0.5, velocityX: 0)

        world.update(size: size, supports: [lower, higher])
        world.advance(elapsed: step, intensity: 0, locked: false)

        XCTAssertGreaterThan(mass(on: higher.id, in: world.frame), 0)
        XCTAssertEqual(mass(on: lower.id, in: world.frame), 0)
    }

    func testMovementTransfersSnowAndFastMotionShedsMore() {
        var stationary = SnowWorld(size: size)
        stationary.update(size: size, supports: [support()])
        fill(&stationary)

        var slow = stationary
        var fast = stationary
        var vertical = stationary
        let startingMass = mass(on: "finder", in: stationary.frame)
        let displacement: CGFloat = 18
        stationary.update(size: size, supports: [support(velocityX: 18)])
        slow.update(size: size, supports: [support(velocityX: 72, offset: displacement)])
        fast.update(size: size, supports: [support(velocityX: 430, offset: displacement)])
        vertical.update(size: size, supports: [support(velocityY: -430)])
        for _ in 0..<12 {
            stationary.advance(elapsed: step, intensity: 0, locked: false)
            slow.advance(elapsed: step, intensity: 0, locked: false)
            fast.advance(elapsed: step, intensity: 0, locked: false)
            vertical.advance(elapsed: step, intensity: 0, locked: false)
        }

        let stationaryMass = mass(on: "finder", in: stationary.frame)
        let slowMass = mass(on: "finder", in: slow.frame)
        let fastMass = mass(on: "finder", in: fast.frame)
        XCTAssertGreaterThanOrEqual(stationaryMass, startingMass)
        XCTAssertLessThan(slowMass, stationaryMass)
        XCTAssertLessThan(fastMass, slowMass)
        let fastDislodged = fast.frame.flakes.filter(\.isDislodged)
        let slowDislodged = slow.frame.flakes.filter(\.isDislodged)
        XCTAssertGreaterThan(fastDislodged.count, slowDislodged.count)
        XCTAssertFalse(slowDislodged.isEmpty)
        XCTAssertTrue(slowDislodged.allSatisfy { $0.velocity.dx < 72 })
        XCTAssertTrue(fastDislodged.allSatisfy { $0.velocity.dx > 0 })
        XCTAssertLessThan(mass(on: "finder", in: vertical.frame), slowMass)
        XCTAssertTrue(vertical.frame.flakes.contains { $0.isDislodged && $0.velocity.dy < -100 })
    }

    func testDislodgedFlakeAcceleratesTowardFloor() throws {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [support()])
        fill(&world)
        world.update(size: size, supports: [support(velocityX: 430)])
        world.advance(elapsed: step, intensity: 0, locked: false)
        let released = try XCTUnwrap(world.frame.flakes.first(where: \.isDislodged))

        world.update(size: size, supports: [])
        world.advance(elapsed: step * 4, intensity: 0, locked: false)
        let falling = try XCTUnwrap(world.frame.flakes.first(where: \.isDislodged))
        XCTAssertLessThan(falling.position.y, released.position.y)
        XCTAssertLessThan(falling.velocity.dy, released.velocity.dy)
    }

    func testDislodgedFlakesEmergeFromExposedSpan() {
        var world = SnowWorld(size: size)
        world.update(size: size, supports: [support()])
        fill(&world, seconds: 30)
        let exposed: Range<CGFloat> = 177..<192
        world.update(size: size, supports: [support(velocityX: 800, visibleRanges: [exposed])])
        world.advance(elapsed: step, intensity: 0, locked: false)

        let released = world.frame.flakes.filter(\.isDislodged)
        XCTAssertFalse(released.isEmpty)
        for flake in released {
            let startXWithoutFlutter = flake.position.x - flake.velocity.dx * step
            XCTAssertGreaterThanOrEqual(startXWithoutFlutter, exposed.lowerBound - 1)
            XCTAssertLessThanOrEqual(startXWithoutFlutter, exposed.upperBound + 1)
        }
    }

    func testZeroIntensityStopsEmittingAndKeepsSettledSnowWhenUnlocked() {
        var world = SnowWorld(size: size)
        fill(&world)
        for _ in 0..<600 {
            world.advance(elapsed: step, intensity: 0, locked: false)
        }
        XCTAssertTrue(world.frame.flakes.isEmpty)
        let before = world.frame
        world.advance(elapsed: step * 2, intensity: 0, locked: false)
        XCTAssertEqual(before, world.frame)
    }

    func testLockedSnowMeltsGraduallyAndSettlesIntoSmallerDrift() {
        var world = SnowWorld(size: size)
        fill(&world, seconds: 85)
        guard let before = world.frame.drifts.first?.heights else {
            return XCTFail("Missing floor drift")
        }
        XCTAssertGreaterThan(before.max() ?? 0, 10)

        world.advance(elapsed: step, intensity: 1, locked: true)
        guard let after = world.frame.drifts.first?.heights else {
            return XCTFail("Missing floor drift")
        }
        for (previous, next) in zip(before, after) {
            XCTAssertGreaterThanOrEqual(next, previous - step)
            if previous > 6 { XCTAssertLessThan(next, previous) }
        }
        for _ in 0..<(15 * 60) {
            world.advance(elapsed: step, intensity: 1, locked: true, floorDepth: 14)
        }
        XCTAssertLessThanOrEqual(world.frame.drifts.first?.heights.max() ?? .infinity, 14)
    }

    func testGroundSnowRetainsDunesEvenAfterProlongedSnowfall() throws {
        var world = SnowWorld(size: size)
        fill(&world, seconds: 150)
        let ground = try XCTUnwrap(world.frame.drifts.first)
        let high = try XCTUnwrap(ground.heights.max())
        let low = try XCTUnwrap(ground.heights.min())
        XCTAssertGreaterThan(low, 0)
        XCTAssertGreaterThan(high - low, 8)
        XCTAssertLessThanOrEqual(high, 40)
    }

    func testLightSnowBuildsFloorDriftThatLastsAfterSnowfallStops() throws {
        var world = SnowWorld(size: size)
        for _ in 0..<(20 * 60) {
            world.advance(elapsed: step, intensity: 0.25, locked: true)
        }
        let peak = try XCTUnwrap(world.frame.drifts.first?.heights.max())
        XCTAssertGreaterThan(peak, 6)
        for _ in 0..<(12 * 60) {
            world.advance(elapsed: step, intensity: 0, locked: true)
        }
        let remaining = try XCTUnwrap(world.frame.drifts.first?.heights.max())
        XCTAssertGreaterThanOrEqual(remaining, peak - 2)
    }

    func testDriftDepthChangesAccumulationWithoutChangingEmission() {
        var shallow = SnowWorld(size: size)
        var deep = shallow
        for _ in 0..<60 {
            shallow.advance(elapsed: step, intensity: 0.25, locked: true, floorDepth: 8)
            deep.advance(elapsed: step, intensity: 0.25, locked: true, floorDepth: 40)
        }
        XCTAssertEqual(shallow.frame.flakes, deep.frame.flakes)
        for _ in 0..<(25 * 60) {
            shallow.advance(elapsed: step, intensity: 0.25, locked: true, floorDepth: 8)
            deep.advance(elapsed: step, intensity: 0.25, locked: true, floorDepth: 40)
        }
        XCTAssertGreaterThan(deep.frame.drifts[0].heights.reduce(0, +), shallow.frame.drifts[0].heights.reduce(0, +))
    }

    func testLargeWakeFrameHasBoundedCatchUp() {
        var wake = SnowWorld(size: size)
        var shortInterval = wake
        wake.advance(elapsed: 3_600, intensity: 1, locked: false)
        shortInterval.advance(elapsed: step * 5, intensity: 1, locked: false)
        XCTAssertEqual(wake.frame, shortInterval.frame)
    }

    func testRenderCadenceDoesNotChangeFixedStepSimulation() {
        var perFrame = SnowWorld(size: size, seed: 1_234)
        var everyOtherFrame = perFrame
        for _ in 0..<180 {
            perFrame.advance(elapsed: step, intensity: 0.7, locked: false)
            perFrame.advance(elapsed: step, intensity: 0.7, locked: false)
            everyOtherFrame.advance(elapsed: step * 2, intensity: 0.7, locked: false)
        }
        XCTAssertEqual(perFrame.frame, everyOtherFrame.frame)
    }

    func testParticleLimitIncludesDislodgedSnow() {
        var world = SnowWorld(size: size, particleLimit: 32)
        world.update(size: size, supports: [support()])
        fill(&world, seconds: 20)
        world.update(size: size, supports: [support(velocityX: 600)])
        for _ in 0..<120 {
            world.advance(elapsed: step, intensity: 1, locked: false)
            XCTAssertLessThanOrEqual(world.frame.flakes.count, 32)
        }
    }

    private func mass(on id: String, in frame: SnowFrame) -> CGFloat {
        frame.drifts.first(where: { $0.id == id })?.heights.reduce(0, +) ?? 0
    }
}
