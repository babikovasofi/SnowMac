import XCTest
@testable import SnowMac

final class DockGeometryTests: XCTestCase {
    func testCompressedDockExpandsToTheMeasuredDisplayWidth() throws {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 74, width: 1470, height: 849)
        )
        let bounds = try XCTUnwrap(display.bottomDockBounds(
            itemCount: 19, preferredTileSize: 55, verticalPadding: 26
        ))

        XCTAssertEqual(bounds.midX, 735)
        XCTAssertEqual(bounds.width, 1398)
        XCTAssertEqual(bounds.height, 74)
        XCTAssertGreaterThan(bounds.minX, 0)
    }

    func testObservedDockUsesLocalPointsAndRejectsFullScreenLayers() throws {
        let frame = CGRect(x: -1200, y: 40, width: 1200, height: 800)
        let display = DisplayGeometry(
            frame: frame, visibleFrame: CGRect(x: -1200, y: 100, width: 1200, height: 715)
        )
        let observed = CGRect(x: -900, y: 49, width: 600, height: 45)
        let dock = try XCTUnwrap(display.localBottomDockBounds(observed: observed, horizontalPadding: 8))
        XCTAssertEqual(dock, CGRect(x: 292, y: 0, width: 616, height: 54))
        XCTAssertNil(display.localBottomDockBounds(observed: frame))
    }

    func testFallbackAllowsDockAtTheMaximumReservedHeight() {
        let display = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 800, height: 400),
            visibleFrame: CGRect(x: 0, y: 100, width: 800, height: 270)
        )
        XCTAssertEqual(display.bottomDockBounds(itemCount: 5)?.height, 100)
    }

    func testHiddenOrSideDockDoesNotInventABottomShelf() {
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let display = DisplayGeometry(frame: frame, visibleFrame: CGRect(x: 70, y: 0, width: 1130, height: 775))
        XCTAssertNil(display.bottomDockBounds(itemCount: 16, preferredTileSize: 55))
        XCTAssertNil(display.localBottomDockBounds(observed: CGRect(x: 0, y: 100, width: 70, height: 530)))
        XCTAssertNil(display.localBottomDockBounds(observed: CGRect(x: 300, y: -50, width: 600, height: 58)))
    }
}
