import Foundation

/// The complete, persistable state of a day: plan, what happened, and where the engine is.
public struct SessionSnapshot: Codable, Sendable, Equatable {
    /// The fixed day plan.
    public internal(set) var plan: [PlannedSegment]
    /// One entry per planned segment, in the same order.
    public internal(set) var actuals: [SegmentActual]
    /// The settings in force for future transitions.
    public internal(set) var settings: SessionSettings
    /// The stored state. It does not catch up with the clock on its own; `SessionEngine.state` does.
    public internal(set) var state: SessionState
    /// Present exactly while a segment is running, paused or in overtime.
    public internal(set) var openInterval: OpenInterval?
    /// An ordinary day or a quick session. Files written before this existed read as a day.
    public internal(set) var kind: SessionKind

    /// No day loaded.
    public static let empty = SessionSnapshot(
        plan: [], actuals: [], settings: SessionSettings(), state: .idle, openInterval: nil
    )

    init(
        plan: [PlannedSegment], actuals: [SegmentActual], settings: SessionSettings,
        state: SessionState, openInterval: OpenInterval?, kind: SessionKind = .day
    ) {
        self.plan = plan
        self.actuals = actuals
        self.settings = settings
        self.state = state
        self.openInterval = openInterval
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case plan, actuals, settings, state, openInterval, kind
    }

    /// Reads a snapshot, taking `kind` as `.day` when it is absent, as in every file written before it existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode([PlannedSegment].self, forKey: .plan)
        actuals = try container.decode([SegmentActual].self, forKey: .actuals)
        settings = try container.decode(SessionSettings.self, forKey: .settings)
        state = try container.decode(SessionState.self, forKey: .state)
        openInterval = try container.decodeIfPresent(OpenInterval.self, forKey: .openInterval)
        kind = try container.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plan, forKey: .plan)
        try container.encode(actuals, forKey: .actuals)
        try container.encode(settings, forKey: .settings)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(openInterval, forKey: .openInterval)
        try container.encode(kind, forKey: .kind)
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

    /// Checks that a snapshot read back from storage is internally consistent.
    func validate() throws(SessionError) {
        guard Self.isWellFormed(plan), actuals.count == plan.count else { throw .invalidSnapshot }
        guard let index = currentIndex else {
            guard openInterval == nil else { throw .invalidSnapshot }
            return
        }
        guard plan.indices.contains(index), let open = openInterval else { throw .invalidSnapshot }
        switch state {
        case let .running(_, endsAt): guard endsAt >= open.start else { throw .invalidSnapshot }
        case let .paused(_, remaining): guard remaining >= 0 else { throw .invalidSnapshot }
        case let .overtime(_, since): guard since >= open.start else { throw .invalidSnapshot }
        case .idle, .finished: break
        }
    }

    /// Segments are indexed by position, have positive length, and follow each other exactly.
    static func isWellFormed(_ plan: [PlannedSegment]) -> Bool {
        for (position, segment) in plan.enumerated() {
            guard segment.index == position, segment.end > segment.start else { return false }
            if position > 0, plan[position - 1].end != segment.start { return false }
        }
        return true
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
        case (.running, .append), (.paused, .append), (.overtime, .append): kind == .quick
        case (.running, .endDay), (.paused, .endDay), (.overtime, .endDay): true
        default: false
        }
    }
}
