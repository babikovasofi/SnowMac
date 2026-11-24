import CoreGraphics
import Foundation

struct SnowSurface {
    var support: SnowSupport
    var heights: [CGFloat]

    init(_ support: SnowSupport) {
        self.support = support
        heights = Array(repeating: 0, count: Self.columnCount(support))
    }

    var columnWidth: CGFloat {
        (support.maxX - support.minX) / CGFloat(heights.count)
    }

    func column(at x: CGFloat) -> Int? {
        guard support.visibleRanges.contains(where: { $0.contains(x) }) else { return nil }
        return min(heights.count - 1, Int((x - support.minX) / columnWidth))
    }

    func bounds(of column: Int) -> Range<CGFloat> {
        let left = support.minX + CGFloat(column) * columnWidth
        return left..<min(support.maxX, left + columnWidth)
    }

    func exposedBounds(of column: Int) -> Range<CGFloat>? {
        let bounds = bounds(of: column)
        for span in support.visibleRanges where span.overlaps(bounds) {
            return max(span.lowerBound, bounds.lowerBound)..<min(span.upperBound, bounds.upperBound)
        }
        return nil
    }

    var drifts: [SnowDrift] {
        support.visibleRanges.map { span in
            let start = max(0, Int((span.lowerBound - support.minX) / columnWidth))
            let end = min(heights.count, Int(ceil((span.upperBound - support.minX) / columnWidth)))
            return SnowDrift(id: support.id.isEmpty ? nil : support.id,
                             left: span.lowerBound, right: span.upperBound, baseY: support.y,
                             firstColumnX: support.minX + CGFloat(start) * columnWidth,
                             columnWidth: columnWidth, heights: Array(heights[start..<end]))
        }
    }

    mutating func reshape(to next: SnowSupport) {
        let columns = Self.columnCount(next)
        if columns < heights.count {
            heights.removeLast(heights.count - columns)
        } else if columns > heights.count {
            heights += Array(repeating: 0, count: columns - heights.count)
        }
        support = next
    }

    mutating func deposit(at column: Int, radius: CGFloat, limit: CGFloat) {
        for neighbor in max(0, column - 1)...min(heights.count - 1, column + 1) {
            let profile = accumulationProfile(at: neighbor)
            let localLimit = limit * profile
            guard heights[neighbor] < localLimit else { continue }
            let share: CGFloat = neighbor == column ? 0.65 : 0.18
            heights[neighbor] = min(localLimit, heights[neighbor] + radius * share * profile)
        }
    }

    private func accumulationProfile(at column: Int) -> CGFloat {
        let position = (CGFloat(column) + 0.5) / CGFloat(heights.count)
        if support.id == "dock" {
            return 0.67 + 0.20 * sin(position * 29.3 + 0.8) + 0.13 * sin(position * 68.1)
        }
        guard support.id.isEmpty else { return 1 }
        return 0.76 + 0.16 * sin(position * 15.1) + 0.08 * sin(position * 42.7 + 1.4)
    }

    mutating func sweep(at x: CGFloat, radius: CGFloat, direction: CGFloat, leavesPile: Bool = true) -> CGFloat {
        guard !heights.isEmpty, columnWidth > 0, x.isFinite else { return 0 }
        let width = CGFloat(heights.count)
        let first = Int(max(0, min(width, ((x - radius - support.minX) / columnWidth).rounded(.down))))
        let end = Int(max(0, min(width, ceil((x + radius - support.minX) / columnWidth))))
        guard first < end else { return 0 }
        var removed: CGFloat = 0
        for index in first..<end where exposedBounds(of: index) != nil {
            removed += heights[index]
            heights[index] = 0
        }
        let front = direction >= 0 ? end : first - 1
        if leavesPile && heights.indices.contains(front), exposedBounds(of: front) != nil {
            heights[front] += min(22, removed * 0.13)
        }
        return removed
    }

    mutating func gather(at x: CGFloat) -> CGFloat {
        guard let column = column(at: x) else { return 0 }
        var removed: CGFloat = 0
        for index in max(0, column - 1)...min(heights.count - 1, column + 1)
            where exposedBounds(of: index) != nil {
            let amount = min(heights[index], index == column ? 3 : 1.4)
            heights[index] -= amount
            removed += amount
        }
        return removed
    }

    mutating func melt(dt: CGFloat, rate: CGFloat = 0.95, downTo minimum: CGFloat = 2) {
        for column in heights.indices where heights[column] > minimum {
            heights[column] = max(minimum, heights[column] - dt * rate)
        }
    }

    private static func columnCount(_ support: SnowSupport) -> Int {
        max(1, Int(ceil((support.maxX - support.minX) / 8)))
    }
}
