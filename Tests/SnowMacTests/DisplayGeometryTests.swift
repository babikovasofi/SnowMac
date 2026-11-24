import AppKit
import XCTest
@testable import SnowMac

final class DisplayGeometryTests: XCTestCase {
    func testQuartzMappingUsesPointsRelativeToPrimaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1_500, height: 1_000)

        XCTAssertEqual(
            DisplayGeometry.appKitRect(
                for: CGRect(x: -100, y: -200, width: 300, height: 150),
                primaryFrame: primary
            ),
            CGRect(x: -100, y: 1_050, width: 300, height: 150)
        )
        XCTAssertEqual(
            DisplayGeometry.appKitRect(
                for: CGRect(x: 1_400, y: 40, width: 500, height: 300),
                primaryFrame: primary
            ),
            CGRect(x: 1_400, y: 660, width: 500, height: 300)
        )
    }

    func testWindowSpanningDisplaysProducesLocalEdgeOnEachDisplay() {
        let leftFrame = CGRect(x: -1_200, y: -400, width: 1_200, height: 1_400)
        let rightFrame = CGRect(x: 0, y: 0, width: 1_500, height: 1_000)
        let windows = [window(1, CGRect(x: -100, y: 300, width: 300, height: 200))]

        let left = DesktopSupports.surfaces(
            for: windows, on: DisplayGeometry(frame: leftFrame, visibleFrame: leftFrame)
        )
        let right = DesktopSupports.surfaces(
            for: windows, on: DisplayGeometry(frame: rightFrame, visibleFrame: rightFrame)
        )

        XCTAssertEqual(left.flatMap(\.visibleRanges), [1_100..<1_200])
        XCTAssertEqual(right.flatMap(\.visibleRanges), [0..<200])
        XCTAssertEqual(left.map(\.y), [900])
        XCTAssertEqual(right.map(\.y), [500])
    }

    func testOccluderSplitsAndRemovalRestoresSupport() {
        let frame = CGRect(x: 0, y: 0, width: 650, height: 450)
        let display = DisplayGeometry(frame: frame, visibleFrame: frame)
        let support = window(1, CGRect(x: 50, y: 50, width: 500, height: 150))
        let foreground = window(2, CGRect(x: 200, y: 150, width: 125, height: 170), isSupport: false)

        XCTAssertEqual(
            DesktopSupports.surfaces(for: [foreground, support], on: display).flatMap(\.visibleRanges),
            [50..<200, 325..<550]
        )
        let split = DesktopSupports.surfaces(for: [foreground, support], on: display)
        let restored = DesktopSupports.surfaces(for: [support], on: display)
        XCTAssertEqual(restored.flatMap(\.visibleRanges), [50..<550])
        XCTAssertEqual(split.map(\.id), restored.map(\.id))
        XCTAssertEqual(split.map(\.xRange), restored.map(\.xRange))

        let hidden = window(3, CGRect(x: 25, y: 180, width: 550, height: 200), isSupport: false)
        let covered = DesktopSupports.surfaces(for: [hidden, support], on: display)
        XCTAssertEqual(covered.map(\.id), restored.map(\.id))
        XCTAssertTrue(covered.flatMap(\.visibleRanges).isEmpty)
        XCTAssertTrue(DesktopSupports.surfaces(for: [foreground], on: display).isEmpty)
    }

    func testSystemRegionIsExcludedFromSupports() {
        let frame = CGRect(x: 0, y: 0, width: 650, height: 450)
        let visible = CGRect(x: 55, y: 0, width: 595, height: 424)
        let display = DisplayGeometry(frame: frame, visibleFrame: visible)
        let low = window(1, CGRect(x: 10, y: 50, width: 120, height: 150))
        let high = window(2, CGRect(x: 10, y: 360, width: 120, height: 80))

        XCTAssertEqual(DesktopSupports.surfaces(for: [high, low], on: display).flatMap(\.visibleRanges), [55..<130])
    }

    func testMotionUsesRealTimeAndResetsOnMissingSnapshot() {
        var motion = WindowMotion()
        let start = window(1, CGRect(x: 0, y: 0, width: 300, height: 250))
        let next = window(1, start.frame.offsetBy(dx: -12, dy: 24))

        XCTAssertTrue(motion.update(windows: [start], timestamp: 10).isEmpty)
        let velocity = motion.update(windows: [next], timestamp: 10.05)[start.identity]
        XCTAssertEqual(velocity?.dx ?? 0, -240, accuracy: 0.001)
        XCTAssertEqual(velocity?.dy ?? 0, 480, accuracy: 0.001)
        XCTAssertTrue(motion.update(windows: [], timestamp: 10.1).isEmpty)
        XCTAssertTrue(motion.update(windows: [start], timestamp: 10.15).isEmpty)
        XCTAssertTrue(motion.update(windows: [next], timestamp: 12).isEmpty)
    }

    func testMotionRejectsResizeAndTeleport() {
        var motion = WindowMotion()
        let start = window(1, CGRect(x: 0, y: 0, width: 300, height: 250))
        let resized = window(1, start.frame.insetBy(dx: -1, dy: -1))
        let distant = window(1, resized.frame.offsetBy(dx: 500, dy: 0))

        _ = motion.update(windows: [start], timestamp: 0)
        XCTAssertTrue(motion.update(windows: [resized], timestamp: 0.05).isEmpty)
        XCTAssertTrue(motion.update(windows: [distant], timestamp: 0.1).isEmpty)
    }

    func testMissingWindowSnapshotRestoresDesktopPresentation() {
        let frame = CGRect(x: 0, y: 0, width: 650, height: 450)
        let display = DisplayGeometry(frame: frame, visibleFrame: frame)
        let fullscreen = window(1, frame)
        let floating = window(2, CGRect(x: 30, y: 40, width: 180, height: 200))

        XCTAssertFalse(DesktopSupports.displayIsVisible(for: [fullscreen], on: display))
        XCTAssertTrue(DesktopSupports.displayIsVisible(for: nil, on: display))
        XCTAssertTrue(DesktopSupports.displayIsVisible(for: [floating, fullscreen], on: display))
    }

    func testBottomDockBoundsUseReservedStripAndLeaveSnowOnBothSides() throws {
        let screen = CGRect(x: -900, y: 0, width: 900, height: 700)
        let active = DisplayGeometry(frame: screen, visibleFrame: CGRect(x: -900, y: 70, width: 900, height: 630))
        let dock = try XCTUnwrap(active.bottomDockBounds(itemCount: 8))
        XCTAssertEqual(dock.midX, screen.width / 2)
        XCTAssertEqual(dock.maxY, 70)
        XCTAssertGreaterThan(dock.minX, 0)
        XCTAssertLessThan(dock.maxX, screen.width)
        let hidden = DisplayGeometry(frame: screen, visibleFrame: screen)
        XCTAssertNil(hidden.bottomDockBounds(itemCount: 8))
    }

    func testSnowAppearsOnDesktopAndSnowMacKeepsThePreviousState() {
        let snowMac = "app.snowmac.SnowMac"
        XCTAssertTrue(OverlayCoordinator.showsDesktopSnow(
            bundleIdentifier: "com.apple.finder", snowMacIdentifier: snowMac, previouslyVisible: false
        ))
        XCTAssertFalse(OverlayCoordinator.showsDesktopSnow(
            bundleIdentifier: "com.apple.Safari", snowMacIdentifier: snowMac, previouslyVisible: true
        ))
        XCTAssertTrue(OverlayCoordinator.showsDesktopSnow(
            bundleIdentifier: "com.apple.Safari", snowMacIdentifier: snowMac,
            previouslyVisible: false, hasVisibleForegroundWindow: false
        ))
        XCTAssertFalse(OverlayCoordinator.showsDesktopSnow(
            bundleIdentifier: "com.apple.Safari", snowMacIdentifier: snowMac,
            previouslyVisible: true, hasVisibleForegroundWindow: true
        ))
        for visible in [true, false] {
            XCTAssertEqual(OverlayCoordinator.showsDesktopSnow(
                bundleIdentifier: snowMac, snowMacIdentifier: snowMac, previouslyVisible: visible
            ), visible)
        }
    }

    func testShowDesktopMovesForegroundWindowOutsideUsableScreen() {
        let screen = CGRect(x: 0, y: 50, width: 800, height: 550)
        let offscreen = window(1, CGRect(x: -780, y: 60, width: 800, height: 500))
        let onscreen = window(1, CGRect(x: 0, y: 60, width: 800, height: 500))
        XCTAssertFalse(OverlayCoordinator.hasVisibleWindow(owner: 123, windows: [offscreen], frames: [screen]))
        XCTAssertTrue(OverlayCoordinator.hasVisibleWindow(owner: 123, windows: [onscreen], frames: [screen]))
    }

    @MainActor
    func testNativePanelsRemainPassiveAndLockCancelsMarkerDrag() throws {
        let passive = PassiveSnowPanel(frame: CGRect(x: -500, y: -500, width: 200, height: 200), level: .normal)
        let marker = SnowMarkerWindow(origin: NSPoint(x: -500, y: -500))
        defer {
            passive.orderOut(nil)
            marker.reconcile(locked: true, visibleFrames: [])
        }

        XCTAssertTrue(passive.ignoresMouseEvents)
        XCTAssertTrue(marker.ignoresMouseEvents)
        XCTAssertEqual(marker.frame.size, CGSize(width: 28, height: 28))

        marker.reconcile(locked: false, visibleFrames: [])
        XCTAssertTrue(marker.ignoresMouseEvents)
        marker.reconcile(locked: false, visibleFrames: [CGRect(x: 0, y: 0, width: 200, height: 200)])
        XCTAssertTrue(marker.ignoresMouseEvents)

        marker.reconcile(locked: false, visibleFrames: [marker.frame])
        XCTAssertFalse(marker.ignoresMouseEvents)
        XCTAssertTrue(passive.ignoresMouseEvents)

        let view = try XCTUnwrap(marker.contentView as? SnowMarker)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: marker.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1
        ))
        view.mouseDown(with: event)
        XCTAssertTrue(view.isDragging)

        marker.reconcile(locked: true, visibleFrames: [marker.frame])
        XCTAssertFalse(view.isDragging)
        XCTAssertTrue(marker.ignoresMouseEvents)
        XCTAssertTrue(marker.isVisible)
        marker.reconcile(locked: true, visibleFrames: [])
        XCTAssertFalse(marker.isVisible)
    }

    @MainActor
    func testGameBodyStaysVisibleUnderLockAndReleasesTheMouse() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let display = DisplaySnow(screen: screen)
        let game = SnowGameWindows(display: display)
        defer { game.hide() }

        let existing = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let snowball = SnowBody(id: 1, kind: .ball, center: CGPoint(x: -400, y: -400))
        game.synchronize(bodies: [snowball], locked: false, tool: .none)
        let bodyWindow = try XCTUnwrap(NSApplication.shared.windows.first {
            !existing.contains(ObjectIdentifier($0)) && $0.frame.size == snowball.size
        })
        XCTAssertTrue(bodyWindow.isVisible)
        XCTAssertFalse(bodyWindow.ignoresMouseEvents)

        game.synchronize(bodies: [snowball], locked: true, tool: .shovel)
        XCTAssertTrue(bodyWindow.isVisible)
        XCTAssertTrue(bodyWindow.ignoresMouseEvents)

        game.hide()
        XCTAssertFalse(bodyWindow.isVisible)
    }

    private func window(_ number: CGWindowID, _ frame: CGRect, isSupport: Bool = true) -> DesktopWindow {
        DesktopWindow(identity: .init(number: number, owner: 123), frame: frame, isSupport: isSupport)
    }
}
