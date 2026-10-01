import SwiftUI

/// A cartoon tomato that fills its frame: a seedling while it is small, then green, yellow, red,
/// and bigger and grinning when it has grown past 100%.
struct TomatoArt: View {
    let growth: Double

    var body: some View {
        let look = TomatoLook(growth: growth)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if look.stage == .sprout {
                    SproutArt(side: side)
                } else {
                    FruitArt(look: look, side: side)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct SproutArt: View {
    let side: CGFloat

    var body: some View {
        let line = side * 0.045
        ZStack {
            Ellipse().fill(TomatoPalette.soil.color).frame(width: side * 0.8, height: side * 0.34)
                .overlay(Ellipse().stroke(TomatoPalette.outline.color, lineWidth: line))
                .offset(y: side * 0.28)
            Capsule().fill(TomatoPalette.leaf.color).frame(width: side * 0.07, height: side * 0.34)
                .overlay(Capsule().stroke(TomatoPalette.outline.color, lineWidth: line * 0.7))
                .offset(y: side * 0.02)
            leaf(angle: -38).offset(x: -side * 0.17, y: -side * 0.17)
            leaf(angle: 38).offset(x: side * 0.17, y: -side * 0.17)
        }
    }

    private func leaf(angle: Double) -> some View {
        Ellipse().fill(TomatoPalette.green.color).frame(width: side * 0.3, height: side * 0.17)
            .overlay(Ellipse().stroke(TomatoPalette.outline.color, lineWidth: side * 0.035))
            .rotationEffect(.degrees(angle))
    }
}

private struct FruitArt: View {
    let look: TomatoLook
    let side: CGFloat

    var body: some View {
        let body = TomatoPalette.body(ripeness: look.ripeness)
        let line = side * 0.05
        ZStack {
            // The fruit: a soft, a little squashed ball with a darker underside.
            Ellipse()
                .fill(LinearGradient(colors: [body.color, body.mixed(with: TomatoPalette.outline, 0.22).color], startPoint: .top, endPoint: .bottom))
                .frame(width: side * 0.88, height: side * 0.78)
                .overlay(Ellipse().stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineJoin: .round)))
                .offset(y: side * 0.08)
            // The shine.
            Capsule().fill(Color.white.opacity(0.6)).frame(width: side * 0.17, height: side * 0.08)
                .rotationEffect(.degrees(-35)).offset(x: -side * 0.23, y: -side * 0.1)
            // The stem and the leaves.
            Capsule().fill(TomatoPalette.leaf.color).frame(width: side * 0.07, height: side * 0.13)
                .overlay(Capsule().stroke(TomatoPalette.outline.color, lineWidth: line * 0.7))
                .offset(y: -side * 0.36)
            StarShape(points: 5, innerRatio: 0.42).fill(TomatoPalette.leaf.color)
                .overlay(StarShape(points: 5, innerRatio: 0.42).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line * 0.7, lineJoin: .round)))
                .frame(width: side * 0.34, height: side * 0.34).offset(y: -side * 0.28)
            face
            if look.isBig { sparkles }
        }
    }

    private var face: some View {
        let line = side * 0.04
        return ZStack {
            Circle().fill(TomatoPalette.blush.color.opacity(0.45)).frame(width: side * 0.12).offset(x: -side * 0.25, y: side * 0.2)
            Circle().fill(TomatoPalette.blush.color.opacity(0.45)).frame(width: side * 0.12).offset(x: side * 0.25, y: side * 0.2)
            switch look.face {
            case .sleepy:
                ArcShape(smile: false).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: side * 0.12, height: side * 0.05).offset(x: -side * 0.14, y: side * 0.1)
                ArcShape(smile: false).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: side * 0.12, height: side * 0.05).offset(x: side * 0.14, y: side * 0.1)
                Circle().fill(TomatoPalette.outline.color).frame(width: side * 0.05).offset(y: side * 0.24)
            case .smile, .grin:
                Circle().fill(TomatoPalette.outline.color).frame(width: side * 0.07).offset(x: -side * 0.14, y: side * 0.08)
                Circle().fill(TomatoPalette.outline.color).frame(width: side * 0.07).offset(x: side * 0.14, y: side * 0.08)
                if look.face == .grin {
                    ArcShape(smile: true, closed: true).fill(TomatoPalette.outline.color)
                        .frame(width: side * 0.26, height: side * 0.14).offset(y: side * 0.22)
                } else {
                    ArcShape(smile: true).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .frame(width: side * 0.2, height: side * 0.08).offset(y: side * 0.2)
                }
            }
        }
    }

    private var sparkles: some View {
        ZStack {
            StarShape(points: 4, innerRatio: 0.3).fill(Color.yellow).frame(width: side * 0.16, height: side * 0.16)
                .offset(x: side * 0.4, y: -side * 0.28)
            StarShape(points: 4, innerRatio: 0.3).fill(Color.yellow).frame(width: side * 0.1, height: side * 0.1)
                .offset(x: -side * 0.42, y: -side * 0.36)
        }
    }
}

/// A star with `points` tips; `innerRatio` is how deep the notches go.
struct StarShape: Shape {
    let points: Int
    let innerRatio: Double

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * innerRatio
        var path = Path()
        for step in 0..<(points * 2) {
            let radius = step.isMultiple(of: 2) ? outer : inner
            let angle = Double(step) * .pi / Double(points) - .pi / 2
            let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A smile (curving down), the upper arc of a closed eye, or with `closed` the open mouth of a grin.
struct ArcShape: Shape {
    let smile: Bool
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if closed {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
            path.closeSubpath()
        } else if smile {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        }
        return path
    }
}
