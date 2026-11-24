import CoreGraphics
import XCTest
@testable import SnowMac

final class SnowInputTests: XCTestCase {
    func testGroundAndDockInputStayOutsideTheNativeDock() {
        let dock = CGRect(x: 200, y: 0, width: 200, height: 60)
        let frame = SnowFrame(size: CGSize(width: 600, height: 400), flakes: [], drifts: [
            drift(id: nil, left: 0, width: 600, baseY: 0),
            drift(id: "dock", left: 200, width: 200, baseY: 60)
        ])

        let regions = SnowInputRegions.make(from: frame, dockBounds: dock)
        XCTAssertTrue(regions.allSatisfy { !$0.rect.intersects(dock) })
        XCTAssertTrue(regions.contains { $0.kind == .ground && $0.rect.maxX <= dock.minX })
        XCTAssertTrue(regions.contains { $0.kind == .ground && $0.rect.minX >= dock.maxX })
        XCTAssertTrue(regions.contains { $0.kind == .dock && $0.rect.minY == dock.maxY })
    }

    func testWindowInputUsesOnlyVisibleSnowAndStaysAboveItsEdge() {
        let frame = SnowFrame(size: CGSize(width: 300, height: 180), flakes: [], drifts: [
            SnowDrift(id: "window", left: 55, right: 82, baseY: 121, firstColumnX: 50,
                      columnWidth: 10, heights: [3, 0, 4, 0])
        ])
        let rects = SnowInputRegions.make(from: frame, dockBounds: nil).map(\.rect)
        XCTAssertEqual(rects, [
            CGRect(x: 55, y: 121, width: 5, height: 5),
            CGRect(x: 70, y: 121, width: 10, height: 6)
        ])
    }

    private func drift(id: String?, left: CGFloat, width: CGFloat, baseY: CGFloat) -> SnowDrift {
        SnowDrift(id: id, left: left, right: left + width, baseY: baseY, firstColumnX: left,
                  columnWidth: 10, heights: Array(repeating: 8, count: Int(width / 10)))
    }
}
