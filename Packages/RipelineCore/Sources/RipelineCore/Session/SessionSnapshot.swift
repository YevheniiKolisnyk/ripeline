import Foundation

/// The complete, persistable state of a day: plan, what happened, and where the engine is.
public struct SessionSnapshot: Codable, Sendable, Equatable {
    public internal(set) var plan: [PlannedSegment]
    /// One entry per planned segment, in the same order.
    public internal(set) var actuals: [SegmentActual]
    public internal(set) var settings: SessionSettings
    public internal(set) var state: SessionState
    /// Present exactly while a segment is running, paused or in overtime.
    public internal(set) var openInterval: OpenInterval?

    /// No day loaded.
    public static let empty = SessionSnapshot(
        plan: [], actuals: [], settings: SessionSettings(), state: .idle, openInterval: nil
    )

    init(
        plan: [PlannedSegment], actuals: [SegmentActual], settings: SessionSettings,
        state: SessionState, openInterval: OpenInterval?
    ) {
        self.plan = plan
        self.actuals = actuals
        self.settings = settings
        self.state = state
        self.openInterval = openInterval
    }

    /// The actuals with the open interval closed at `now`, for drawing and totals.
    public func actuals(at now: Date) -> [SegmentActual] {
        var result = actuals
        if let open = openInterval, let index = currentIndex, now > open.start {
            result[index].intervals.append(ActualInterval(kind: open.kind, start: open.start, end: now))
        }
        return result
    }

    /// Index of the segment that is running, paused or in overtime.
    var currentIndex: Int? {
        switch state {
        case let .running(index, _), let .paused(index, _), let .overtime(index, _): index
        case .idle, .finished: nil
        }
    }

    /// The latest instant anything was recorded at. The engine never moves time before it.
    var lastRecordedInstant: Date? {
        let closed = actuals.compactMap { $0.intervals.last?.end }
        return (closed + [openInterval?.start].compactMap { $0 }).max()
    }

    /// Whether `action` is valid in the current state.
    public func isAllowed(_ action: SessionAction) -> Bool {
        switch (state, action) {
        case (.idle, .startDay), (.finished, .startDay): true
        case (.idle, .start): !plan.isEmpty
        case (.idle, .endDay): !plan.isEmpty
        case (.running, .pause): true
        case (.paused, .resume): true
        case (.running, .extend), (.paused, .extend), (.overtime, .extend): true
        case (.running, .skip), (.paused, .skip), (.overtime, .skip): true
        case (.overtime, .advance): true
        case (.running, .endDay), (.paused, .endDay), (.overtime, .endDay): true
        default: false
        }
    }
}
