import Foundation
import Observation
import RipelineCore

/// What the day overview reads. The controller implements it; tests use a real engine behind it.
@MainActor protocol DayOverviewSource: AnyObject {
    var hasDay: Bool { get }
    var overviewPhase: Phase { get }
    var overviewTimeline: Timeline { get }
    var overviewComparison: DayComparison { get }
    var overviewStatus: ScheduleStatus? { get }
    /// The clock's time, not the controller's last update: the marker must move even while paused.
    var overviewNow: Date { get }
    /// The last instant anything was recorded, for a stored day that was never ended; `nil` otherwise.
    var overviewLastRecord: Date? { get }
    /// Whether this is a quick session: it has no plan to be ahead of or behind, so its lag, planned
    /// end and projected end are not shown.
    var overviewIsQuick: Bool { get }
    /// The tomatoes of the day as of `overviewNow`.
    var overviewTomatoes: [Tomato] { get }
}

extension DayOverviewSource {
    var overviewLastRecord: Date? { nil }
    var overviewIsQuick: Bool { false }
    var overviewTomatoes: [Tomato] { [] }
}

/// A block placed on the axis, as fractions of its width.
struct BlockLayout<Kind: Equatable & Sendable>: Equatable, Sendable {
    let kind: Kind
    let start: Date
    let end: Date
    /// Where the block begins, from 0 to 1.
    let x: Double
    /// How wide it is, as a fraction of the axis.
    let width: Double
}

enum LagState: Equatable, Sendable {
    /// Within a minute of the plan, either way.
    case onSchedule
    case behind(TimeInterval)
    case ahead(TimeInterval)
}

/// Plan against reality for the whole day.
struct DaySummary: Equatable, Sendable {
    let focusPlanned: TimeInterval
    let focusActual: TimeInterval
    let restPlanned: TimeInterval
    let restActual: TimeInterval
    /// Paused time that counts as neither work nor rest.
    let untracked: TimeInterval
    let plannedEnd: Date?
    /// The projected end while the day runs, the actual end once it is finished, or the last record
    /// of a day that was never ended; `nil` if unknown.
    let endsAt: Date?
    let endKind: EndKind

    enum EndKind: Equatable, Sendable {
        case projected
        case final
        /// The day was never ended: this is the last thing recorded.
        case lastRecord
    }
}

/// One line of the segment table.
struct SegmentRow: Equatable, Sendable {
    let index: Int
    let start: Date
    let kind: SegmentKind
    let planned: TimeInterval
    let work: TimeInterval
    let rest: TimeInterval
    let untracked: TimeInterval
    let status: SegmentStatus

    var actual: TimeInterval { work + rest + untracked }
    var delta: TimeInterval { actual - planned }
}

/// A tomato placed on the bed: the middle of its work block as a fraction of the axis, and the block's width.
struct BedPlot: Equatable, Sendable, Identifiable {
    let tomato: Tomato
    let x: Double
    let width: Double
    var id: UUID { tomato.id }
}

/// The numbers and positions behind the day screen. The views only draw them.
@MainActor @Observable
final class DayOverviewModel {
    enum Mode: Equatable, Sendable {
        case noDay
        case running
        case finished
    }

    /// Lag within this many seconds of zero counts as on schedule.
    static let onScheduleTolerance: TimeInterval = 60

    @ObservationIgnored private let source: any DayOverviewSource
    @ObservationIgnored private let calendar: Calendar

    private(set) var mode: Mode = .noDay
    /// A quick session: no lag, planned end or projected end.
    private(set) var isQuick = false
    private(set) var axis: TimeAxis?
    private(set) var planned: [BlockLayout<SegmentKind>] = []
    private(set) var actual: [BlockLayout<ActualKind>] = []
    /// The tomatoes that are growing or can be picked, each over its work block.
    private(set) var bed: [BedPlot] = []
    /// Where "now" falls on the axis; only while the day runs.
    private(set) var nowX: Double?
    private(set) var lag: LagState?
    private(set) var summary: DaySummary?
    private(set) var segments: [SegmentRow] = []

    init(source: any DayOverviewSource, calendar: Calendar = .autoupdatingCurrent) {
        self.source = source
        self.calendar = calendar
        refresh()
    }

    /// Re-reads the source. Does nothing visible when nothing changed, and never fails: with no day
    /// every output is empty.
    func refresh() {
        let phase = source.overviewPhase
        guard source.hasDay, phase != .idle else {
            clear()
            return
        }
        mode = phase == .finished ? .finished : .running
        isQuick = source.overviewIsQuick

        let timeline = source.overviewTimeline
        let comparison = source.overviewComparison
        let status = source.overviewStatus
        let now = source.overviewNow

        var dates = timeline.planned.flatMap { [$0.start, $0.end] } + timeline.actual.flatMap { [$0.start, $0.end] }
        if mode == .running { dates.append(now) }
        let axis = TimeAxis(covering: dates, calendar: calendar)
        self.axis = axis

        planned = timeline.planned.map { layout($0.kind, $0.start, $0.end, on: axis) }
        actual = timeline.actual.map { layout($0.kind, $0.start, $0.end, on: axis) }
        bed = source.overviewTomatoes.compactMap { tomato in
            guard tomato.availability == .growing || tomato.availability == .pickable,
                  planned.indices.contains(tomato.segmentIndex) else { return nil }
            let block = planned[tomato.segmentIndex]
            return BedPlot(tomato: tomato, x: block.x + block.width / 2, width: block.width)
        }
        nowX = mode == .running ? axis?.x(for: now) : nil
        // Lag is for a day still going; for a finished day the summary compares the ends.
        lag = mode == .running && !isQuick ? status.map(Self.lagState) : nil

        let totals = comparison.totals
        let end: (date: Date?, kind: DaySummary.EndKind)
        if mode == .running {
            end = (isQuick ? nil : status?.projectedEnd, .projected)
        } else if let actualEnd = totals.actualEnd {
            end = (actualEnd, .final)
        } else if let lastRecord = source.overviewLastRecord {
            end = (lastRecord, .lastRecord)
        } else {
            end = (nil, .final)
        }
        summary = DaySummary(
            focusPlanned: totals.focusPlanned, focusActual: totals.focusActual,
            restPlanned: totals.restPlanned, restActual: totals.restActual,
            untracked: totals.untracked, plannedEnd: isQuick ? nil : totals.plannedEnd,
            endsAt: end.date, endKind: end.kind
        )
        segments = comparison.rows.map {
            SegmentRow(
                index: $0.segment.index, start: $0.segment.start, kind: $0.segment.kind,
                planned: $0.planned, work: $0.work, rest: $0.rest, untracked: $0.untracked, status: $0.status
            )
        }
    }

    private func clear() {
        mode = .noDay
        isQuick = false
        axis = nil
        planned = []
        actual = []
        bed = []
        nowX = nil
        lag = nil
        summary = nil
        segments = []
    }

    private func layout<Kind: Equatable & Sendable>(_ kind: Kind, _ start: Date, _ end: Date, on axis: TimeAxis?) -> BlockLayout<Kind> {
        let from = axis?.x(for: start) ?? 0
        let to = axis?.x(for: end) ?? 0
        return BlockLayout(kind: kind, start: start, end: end, x: from, width: max(0, to - from))
    }

    private static func lagState(_ status: ScheduleStatus) -> LagState {
        let lag = status.lag
        if abs(lag) < onScheduleTolerance { return .onSchedule }
        return lag > 0 ? .behind(lag) : .ahead(-lag)
    }
}
