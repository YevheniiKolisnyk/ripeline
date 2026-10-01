import RipelineCore
import SwiftUI

/// The planned and actual rows on their shared axis, with hour labels, the "now" line and a legend.
/// Plain rectangles from the model's fractions, so it also draws in a headless renderer.
struct TimelineRowsView: View {
    let model: DayOverviewModel
    @Environment(\.locale) private var locale

    private let rowHeight: CGFloat = 28
    private let rowGap: CGFloat = 8
    private let labelWidth: CGFloat = 52
    /// A block is never drawn narrower than this, so a short break stays visible.
    private let minimumBlockWidth: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing, spacing: rowGap) {
                    Text("overview.plan").frame(height: rowHeight)
                    Text("overview.actual").frame(height: rowHeight)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)

                GeometryReader { proxy in
                    tracks(width: proxy.size.width)
                }
                .frame(height: rowHeight * 2 + rowGap + 24)
            }
            legend
        }
    }

    // MARK: Tracks

    private func tracks(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ticks(width: width)
            row(model.planned, width: width, emphasis: 0.4, label: { OverviewText.plannedBlockLabel($0, locale: locale, timeZone: .autoupdatingCurrent) },
                kindName: { SetupText.kindName($0.kind) })
                .offset(y: 0)
            row(model.actual, width: width, emphasis: 1, label: { OverviewText.actualBlockLabel($0, locale: locale, timeZone: .autoupdatingCurrent) },
                kindName: { OverviewText.actualKindName($0.kind) })
                .offset(y: rowHeight + rowGap)
            if let nowX = model.nowX { nowLine(at: nowX * width) }
        }
    }

    private func row<Kind: Equatable & Sendable>(
        _ blocks: [BlockLayout<Kind>], width: CGFloat, emphasis: Double,
        label: @escaping (BlockLayout<Kind>) -> String, kindName: @escaping (BlockLayout<Kind>) -> String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)).frame(width: width, height: rowHeight)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                let drawn = max(CGFloat(block.width) * width, minimumBlockWidth)
                let height = Self.height(for: block.kind, full: rowHeight)
                BlockShape(kind: block.kind, emphasis: emphasis)
                    .frame(width: drawn, height: height)
                    .offset(x: min(CGFloat(block.x) * width, max(0, width - drawn)), y: (rowHeight - height) / 2)
                    .help(OverviewText.tooltip(kindName: kindName(block), start: block.start, end: block.end, locale: locale, timeZone: .autoupdatingCurrent))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(block))
            }
        }
        .frame(width: width, height: rowHeight, alignment: .topLeading)
    }

    /// Work is the full height; breaks and paused time are lower, so colour is not the only cue.
    private static func height<Kind>(for kind: Kind, full: CGFloat) -> CGFloat {
        if let planned = kind as? SegmentKind { return planned == .work ? full : full * 0.6 }
        if let actual = kind as? ActualKind { return actual == .work ? full : full * 0.6 }
        return full
    }

    // MARK: Axis

    private func ticks(width: CGFloat) -> some View {
        let axis = model.axis
        let ticks = axis?.ticks ?? []
        let spacing = ticks.count > 1 ? width / CGFloat(ticks.count - 1) : width
        let stride = max(1, Int((52 / max(spacing, 1)).rounded(.up)))
        let top = rowHeight * 2 + rowGap
        return ZStack(alignment: .topLeading) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: top).offset(x: tick.x * width)
                if index % stride == 0 {
                    Text(verbatim: SetupText.time(tick.date, locale: locale, timeZone: .autoupdatingCurrent))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: min(max(tick.x * width - 14, 0), max(0, width - 30)), y: top + 4)
                }
            }
        }
    }

    private func nowLine(at x: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.red).frame(width: 1.5, height: rowHeight * 2 + rowGap).offset(x: x - 0.75)
            Text("overview.now").font(.caption2).foregroundStyle(.red).fixedSize().offset(x: x + 3, y: -1)
        }
        .accessibilityHidden(true)
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(BlockShape(kind: SegmentKind.work, emphasis: 1), "setup.work")
            swatch(BlockShape(kind: SegmentKind.shortBreak, emphasis: 1), "setup.shortBreak")
            swatch(BlockShape(kind: SegmentKind.longBreak, emphasis: 1), "setup.longBreak")
            swatch(BlockShape(kind: ActualKind.untracked, emphasis: 1), "summary.untracked")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, labelWidth + 8)
        .accessibilityHidden(true)
    }

    private func swatch(_ shape: BlockShape, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            shape.frame(width: 14, height: 10)
            Text(title)
        }
    }
}

/// One block: a rounded rectangle in the colour of its kind, hatched when it is untracked time.
struct BlockShape: View {
    let colour: Color
    let hatched: Bool

    init<Kind>(kind: Kind, emphasis: Double) {
        let base: Color
        var hatched = false
        if let planned = kind as? SegmentKind {
            switch planned {
            case .work: base = .accentColor
            case .shortBreak: base = .green
            case .longBreak: base = .teal
            }
        } else if let actual = kind as? ActualKind {
            switch actual {
            case .work: base = .accentColor
            case .rest: base = .green
            case .untracked: base = .gray; hatched = true
            }
        } else {
            base = .gray
        }
        self.colour = base.opacity(emphasis)
        self.hatched = hatched
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(colour)
            .overlay { if hatched { HatchLines().stroke(Color.primary.opacity(0.45), lineWidth: 1).clipShape(RoundedRectangle(cornerRadius: 3)) } }
    }
}

/// Diagonal lines across a rectangle, to mark time that is counted as neither work nor rest.
struct HatchLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 5
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}
