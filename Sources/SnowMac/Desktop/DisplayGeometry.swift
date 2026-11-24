import CoreGraphics
import Foundation

struct DisplayGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect

    func bottomDockBounds(
        itemCount: Int,
        preferredTileSize: CGFloat? = nil,
        verticalPadding: CGFloat = 20
    ) -> CGRect? {
        let reserved = visibleFrame.minY - frame.minY
        guard reserved >= 24, reserved <= frame.height / 4,
              visibleFrame.width >= frame.width - 2 else { return nil }
        let tileSize = max(12, reserved - verticalPadding)
        let maxWidth = frame.width - 2 * max(8, tileSize * 0.75)
        let compressed = preferredTileSize.map { $0 - tileSize >= 4 } ?? false
        let estimatedWidth = CGFloat(max(itemCount, 2)) * (tileSize + 8) + 12
        let width = compressed ? maxWidth : min(maxWidth, estimatedWidth)
        guard width > 0 else { return nil }
        return CGRect(x: (frame.width - width) / 2, y: 0, width: width, height: reserved)
    }

    func localBottomDockBounds(observed bounds: CGRect, horizontalPadding: CGFloat = 0) -> CGRect? {
        let clipped = bounds.intersection(frame)
        guard !clipped.isNull, bounds.width > bounds.height * 1.5,
              bounds.height < frame.height / 4, bounds.midY < frame.minY + frame.height / 4,
              clipped.height >= 20, clipped.width >= 48 else { return nil }
        let left = max(frame.minX, clipped.minX - horizontalPadding)
        let right = min(frame.maxX, clipped.maxX + horizontalPadding)
        let top = clipped.maxY - frame.minY
        return CGRect(x: left - frame.minX, y: 0, width: right - left, height: top)
    }

    static func appKitRect(for quartzRect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(
            x: primaryFrame.minX + quartzRect.minX,
            y: primaryFrame.maxY - quartzRect.maxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }
}

struct DesktopWindow: Equatable {
    struct Identity: Hashable {
        let number: CGWindowID
        let owner: Int32
    }

    let identity: Identity
    let frame: CGRect
    let isSupport: Bool
}

struct WindowSurface: Equatable {
    let identity: DesktopWindow.Identity
    let xRange: Range<CGFloat>
    let visibleRanges: [Range<CGFloat>]
    let y: CGFloat

    var id: String { "window-\(identity.owner)-\(identity.number)" }
}

enum DesktopSupports {
    static func displayIsVisible(for windows: [DesktopWindow]?, on display: DisplayGeometry) -> Bool {
        let frame = display.frame
        let frontWindow = windows?.first { $0.isSupport && $0.frame.intersects(frame) }
        return frontWindow?.frame.insetBy(dx: -1, dy: -1).contains(frame) != true
    }

    static func surfaces(
        for windows: [DesktopWindow],
        on display: DisplayGeometry
    ) -> [WindowSurface] {
        var surfaces: [WindowSurface] = []
        let origin = display.frame.minX
        for (index, window) in windows.enumerated() where window.isSupport {
            let top = window.frame.maxY
            let left = max(window.frame.minX, display.visibleFrame.minX)
            let right = min(window.frame.maxX, display.visibleFrame.maxX)
            guard top > display.visibleFrame.minY, top < display.visibleFrame.maxY,
                  right > left else { continue }

            var ranges = [left..<right]
            for occluder in windows.prefix(index) {
                let frame = occluder.frame
                // Keep the snow above the covered edge of the supporting window.
                guard frame.minY < top + 14, frame.maxY >= top else { continue }
                ranges = ranges.flatMap { subtract(frame.minX..<frame.maxX, from: $0) }
                if ranges.isEmpty { break }
            }

            let visibleRanges = ranges.filter { $0.upperBound - $0.lowerBound >= 5 }
                .map { ($0.lowerBound - origin)..<($0.upperBound - origin) }
            surfaces.append(
                WindowSurface(
                    identity: window.identity,
                    xRange: (window.frame.minX - origin)..<(window.frame.maxX - origin),
                    visibleRanges: visibleRanges,
                    y: top - display.frame.minY
                )
            )
        }
        return surfaces
    }

    private static func subtract(_ cut: Range<CGFloat>, from whole: Range<CGFloat>) -> [Range<CGFloat>] {
        let lower = max(whole.lowerBound, cut.lowerBound)
        let upper = min(whole.upperBound, cut.upperBound)
        guard lower < upper else { return [whole] }
        var result: [Range<CGFloat>] = []
        if whole.lowerBound < lower { result.append(whole.lowerBound..<lower) }
        if upper < whole.upperBound { result.append(upper..<whole.upperBound) }
        return result
    }
}

struct WindowMotion {
    private var previousFrames: [DesktopWindow.Identity: CGRect] = [:]
    private var previousTimestamp: TimeInterval?

    mutating func reset() {
        previousFrames.removeAll()
        previousTimestamp = nil
    }

    mutating func update(
        windows: [DesktopWindow],
        timestamp: TimeInterval
    ) -> [DesktopWindow.Identity: CGVector] {
        var frames: [DesktopWindow.Identity: CGRect] = [:]
        for window in windows where window.isSupport {
            frames[window.identity] = window.frame
        }
        defer {
            previousFrames = frames
            previousTimestamp = timestamp
        }

        guard let previousTimestamp else { return [:] }
        let elapsed = timestamp - previousTimestamp
        guard elapsed >= 0.005, elapsed <= 0.20 else { return [:] }

        var motion: [DesktopWindow.Identity: CGVector] = [:]
        for (identity, frame) in frames {
            guard let previous = previousFrames[identity],
                  previous.size == frame.size else { continue }
            let dx = frame.minX - previous.minX
            let dy = frame.minY - previous.minY
            guard hypot(dx, dy) < 240 else { continue }
            motion[identity] = CGVector(dx: dx / elapsed, dy: dy / elapsed)
        }
        return motion
    }
}
