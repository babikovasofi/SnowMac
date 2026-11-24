import SwiftUI

enum SnowLayer {
    case all
    case falling
    case settled
}

struct SnowView: View {
    let frame: SnowFrame
    var layer: SnowLayer = .all
    var dockBounds: CGRect?
    var plow: CGPoint?
    var plowLoad: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            if layer != .falling {
                for drift in frame.drifts {
                    draw(drift, in: context, height: size.height)
                }
            }
            var smallFlakes = Path()
            var brightFlakes = Path()
            var powder = Path()
            for flake in frame.flakes where layer == .all || flake.isDislodged == (layer == .settled) {
                let radius = flake.radius
                let rect = CGRect(x: flake.position.x - radius, y: size.height - flake.position.y - radius,
                                  width: radius * 2, height: radius * 2)
                if flake.isDislodged {
                    powder.addEllipse(in: rect)
                } else if radius < 1.45 {
                    smallFlakes.addEllipse(in: rect)
                } else {
                    brightFlakes.addEllipse(in: rect)
                }
            }
            context.fill(smallFlakes, with: .color(.white.opacity(0.22)))
            context.fill(brightFlakes, with: .color(.white.opacity(0.40)))
            context.fill(powder, with: .color(.white.opacity(0.75)))
            if let plow {
                drawSnowplow(in: context, at: CGPoint(x: plow.x, y: size.height - plow.y), snowLoad: plowLoad)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func draw(_ drift: SnowDrift, in context: GraphicsContext, height: CGFloat) {
        let baseline = height - drift.baseY
        let heights = drift.heights.indices.map { index in
            let x = drift.firstColumnX + (CGFloat(index) + 0.5) * drift.columnWidth
            return drift.heights[index] * driftScale(at: x, drift: drift)
        }
        var start: Int?
        for index in 0...drift.heights.count {
            if index < heights.count && heights[index] > 0.15 {
                if start == nil { start = index }
            } else if let first = start {
                drawRun(first..<index, drift: drift, heights: heights, baseline: baseline, context: context)
                start = nil
            }
        }
    }

    private func driftScale(at x: CGFloat, drift: SnowDrift) -> CGFloat {
        SnowInputRegions.depthScale(at: x, drift: drift, dockBounds: dockBounds)
    }

    private func drawRun(_ columns: Range<Int>, drift: SnowDrift, heights: [CGFloat], baseline: CGFloat, context: GraphicsContext) {
        let left = max(drift.left, drift.firstColumnX + CGFloat(columns.lowerBound) * drift.columnWidth)
        let right = min(drift.right, drift.firstColumnX + CGFloat(columns.upperBound) * drift.columnWidth)
        var outline = Path()
        outline.move(to: CGPoint(x: left, y: baseline))
        var previous = CGPoint(x: left, y: baseline)
        for index in columns {
            let columnLeft = drift.firstColumnX + CGFloat(index) * drift.columnWidth
            let peakX = (max(left, columnLeft) + min(right, columnLeft + drift.columnWidth)) * 0.5
            let peak = CGPoint(x: peakX, y: baseline - heights[index])
            let midpoint = (previous.x + peak.x) * 0.5
            outline.addCurve(to: peak,
                             control1: CGPoint(x: midpoint, y: previous.y),
                             control2: CGPoint(x: midpoint, y: peak.y))
            previous = peak
        }
        outline.addQuadCurve(to: CGPoint(x: right, y: baseline),
                             control: CGPoint(x: right, y: previous.y))
        outline.closeSubpath()
        let isGround = drift.id == nil || drift.id == "dock"
        let snowColors = [
            Color.white.opacity(isGround ? 0.96 : 0.67),
            Color(red: 0.78, green: 0.88, blue: 0.97).opacity(isGround ? 0.84 : 0.45)
        ]
        context.fill(outline, with: .linearGradient(
            Gradient(colors: snowColors),
            startPoint: CGPoint(x: left, y: outline.boundingRect.minY),
            endPoint: CGPoint(x: left, y: baseline)
        ))
    }
}
