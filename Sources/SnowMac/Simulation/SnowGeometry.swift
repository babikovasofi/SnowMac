import CoreGraphics
import Foundation

struct SnowSupport: Equatable {
    let id: String
    let minX: CGFloat
    let maxX: CGFloat
    let y: CGFloat
    let velocityX: CGFloat
    let velocityY: CGFloat
    let visibleRanges: [Range<CGFloat>]

    init(id: String, minX: CGFloat, maxX: CGFloat, y: CGFloat,
         velocityX: CGFloat, velocityY: CGFloat = 0, visibleRanges: [Range<CGFloat>]? = nil) {
        self.id = id
        self.minX = minX
        self.maxX = maxX
        self.y = y
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.visibleRanges = visibleRanges ?? (maxX > minX ? [minX..<maxX] : [])
    }
}

struct SnowFlake: Equatable {
    var position: CGPoint
    var velocity: CGVector
    let radius: CGFloat
    let phase: CGFloat
    let sourceSupportID: String?

    var isDislodged: Bool { sourceSupportID != nil }
}

struct SnowDrift: Equatable {
    let id: String?
    let left: CGFloat
    let right: CGFloat
    let baseY: CGFloat
    let firstColumnX: CGFloat
    let columnWidth: CGFloat
    let heights: [CGFloat]
}

struct SnowFrame: Equatable {
    let size: CGSize
    let flakes: [SnowFlake]
    let drifts: [SnowDrift]
}
