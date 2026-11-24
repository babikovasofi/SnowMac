import SwiftUI

struct SnowBodyArt: View {
    let kind: SnowBodyKind

    private var frost: LinearGradient {
        LinearGradient(colors: [.white, Color(red: 0.69, green: 0.83, blue: 0.93)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            switch kind {
            case .ball:
                Circle().fill(frost).padding(1)
                    .overlay(alignment: .topLeading) {
                        Circle().fill(.white.opacity(0.75))
                            .frame(width: size.width * 0.22)
                            .offset(x: size.width * 0.22, y: size.height * 0.18)
                    }
            case .brick:
                RoundedRectangle(cornerRadius: 4).fill(frost).padding(1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                            .padding(3)
                    }
            case .snowman:
                snowman(size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func snowman(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Circle().fill(frost)
                .frame(width: size.width * 0.90)
                .position(x: size.width / 2, y: size.height * 0.76)
            Circle().fill(frost)
                .frame(width: size.width * 0.70)
                .position(x: size.width / 2, y: size.height * 0.52)
            Circle().fill(frost)
                .frame(width: size.width * 0.56)
                .position(x: size.width / 2, y: size.height * 0.30)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.56, green: 0.12, blue: 0.16))
                .frame(width: size.width * 0.53, height: max(2, size.height * 0.07))
                .rotationEffect(.degrees(-8))
                .position(x: size.width / 2, y: size.height * 0.44)
            HStack(spacing: size.width * 0.09) {
                Circle().fill(.black.opacity(0.8))
                Circle().fill(.black.opacity(0.8))
            }
            .frame(width: size.width * 0.25, height: max(2, size.width * 0.055))
            .position(x: size.width / 2, y: size.height * 0.28)
            Capsule()
                .fill(.orange)
                .frame(width: max(3, size.width * 0.17), height: max(1.5, size.width * 0.05))
                .rotationEffect(.degrees(-10))
                .position(x: size.width * 0.55, y: size.height * 0.34)
        }
    }
}

func drawSnowplow(in canvas: GraphicsContext, at center: CGPoint, snowLoad: CGFloat) {
    var context = canvas
    context.translateBy(x: center.x, y: center.y)
    context.scaleBy(x: -1, y: 1)
    let left: CGFloat = -28
    let top: CGFloat = -13
    let pileHeight = min(1, max(0, snowLoad)) * 29
    if pileHeight > 1 {
        let bladeTip: CGFloat = 29
        let ground: CGFloat = 17
        var mound = Path()
        mound.move(to: CGPoint(x: bladeTip - 4, y: ground))
        mound.addQuadCurve(to: CGPoint(x: bladeTip + 5 + pileHeight, y: ground),
                           control: CGPoint(x: bladeTip + 1, y: ground - pileHeight * 1.8))
        mound.closeSubpath()
        context.fill(mound, with: .color(Color(red: 0.90, green: 0.96, blue: 1)))
    }
    var chassis = Path(roundedRect: CGRect(x: left, y: top + 10, width: 48, height: 17),
                       cornerRadius: 5)
    chassis.addRoundedRect(in: CGRect(x: left + 8, y: top, width: 23, height: 19),
                           cornerSize: CGSize(width: 5, height: 5))
    context.fill(chassis, with: .color(Color(red: 0.19, green: 0.45, blue: 0.59)))
    let window = Path(roundedRect: CGRect(x: left + 13, y: top + 3, width: 13, height: 10),
                      cornerRadius: 2)
    context.fill(window, with: .color(Color(red: 0.82, green: 0.94, blue: 0.98)))
    let beacon = Path(roundedRect: CGRect(x: left + 17, y: top - 3, width: 7, height: 4),
                      cornerRadius: 2)
    context.fill(beacon, with: .color(.orange))
    for offset in [9.0, 35.0] {
        let wheel = Path(ellipseIn: CGRect(x: left + offset, y: top + 20, width: 11, height: 11))
        let hub = Path(ellipseIn: CGRect(x: left + offset + 3, y: top + 23, width: 5, height: 5))
        context.fill(wheel, with: .color(Color(red: 0.14, green: 0.21, blue: 0.27)))
        context.fill(hub, with: .color(.white.opacity(0.75)))
    }
    var blade = Path()
    blade.move(to: CGPoint(x: left + 42, y: top + 25))
    blade.addLine(to: CGPoint(x: left + 61, y: top + 15))
    blade.addQuadCurve(to: CGPoint(x: left + 60, y: top + 30),
                      control: CGPoint(x: left + 56, y: top + 24))
    blade.addLine(to: CGPoint(x: left + 44, y: top + 30))
    blade.closeSubpath()
    context.fill(blade, with: .color(Color(red: 0.87, green: 0.66, blue: 0.29)))
}
