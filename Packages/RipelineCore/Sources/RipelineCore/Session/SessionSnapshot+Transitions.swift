import Foundation

/// State transitions. Each takes the instant it happens at; the engine supplies it from its clock.
extension SessionSnapshot {
    mutating func startDay(plan: [PlannedSegment], settings: SessionSettings) throws(SessionError) {
        guard isAllowed(.startDay) else { throw .notAllowed(.startDay) }
        guard !plan.isEmpty else { throw .emptyPlan }
        self = SessionSnapshot(
            plan: plan,
            actuals: plan.map { _ in SegmentActual() },
            settings: settings,
            state: .idle,
            openInterval: nil
        )
    }

    mutating func start(at now: Date) throws(SessionError) {
        guard isAllowed(.start) else { throw .notAllowed(.start) }
        begin(segment: 0, at: now)
    }

    mutating func pause(at now: Date) throws(SessionError) {
        guard isAllowed(.pause), case let .running(index, endsAt) = state else { throw .notAllowed(.pause) }
        closeOpenInterval(at: now)
        state = .paused(segmentIndex: index, remaining: max(0, endsAt.timeIntervalSince(now)))
        openInterval = OpenInterval(kind: settings.pausesCountAsRest ? .rest : .untracked, start: now)
    }

    mutating func resume(at now: Date) throws(SessionError) {
        guard isAllowed(.resume), case let .paused(index, remaining) = state else { throw .notAllowed(.resume) }
        closeOpenInterval(at: now)
        state = .running(segmentIndex: index, endsAt: now.addingTimeInterval(remaining))
        openInterval = OpenInterval(kind: runningKind(of: index), start: now)
    }

    mutating func endDay(at now: Date) throws(SessionError) {
        guard isAllowed(.endDay) else { throw .notAllowed(.endDay) }
        if let index = currentIndex {
            closeOpenInterval(at: now)
            actuals[index].status = .skipped
        }
        state = .finished
    }

    // MARK: Building blocks

    /// Starts `segment` running for its planned duration.
    mutating func begin(segment index: Int, at now: Date) {
        actuals[index].status = .active
        state = .running(segmentIndex: index, endsAt: now.addingTimeInterval(plan[index].duration))
        openInterval = OpenInterval(kind: runningKind(of: index), start: now)
    }

    /// Running time in a work segment is work; running time in a break is rest.
    func runningKind(of index: Int) -> ActualKind {
        plan[index].kind == .work ? .work : .rest
    }

    /// Moves the open interval into its segment's history. Zero-length intervals are dropped.
    mutating func closeOpenInterval(at now: Date) {
        defer { openInterval = nil }
        guard let open = openInterval, let index = currentIndex, now > open.start else { return }
        actuals[index].intervals.append(ActualInterval(kind: open.kind, start: open.start, end: now))
    }
}
