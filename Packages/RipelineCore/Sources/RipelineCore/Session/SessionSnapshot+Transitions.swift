import Foundation

/// State transitions. Each takes the instant it happens at; the engine supplies it from its clock.
extension SessionSnapshot {
    mutating func startDay(plan: [PlannedSegment], settings: SessionSettings, kind: SessionKind = .day) throws(SessionError) {
        guard isAllowed(.startDay) else { throw .notAllowed(.startDay) }
        guard !plan.isEmpty else { throw .emptyPlan }
        guard Self.isWellFormed(plan) else { throw .invalidPlan }
        self = SessionSnapshot(
            plan: plan,
            actuals: plan.map { _ in SegmentActual() },
            settings: settings,
            state: .idle,
            openInterval: nil,
            kind: kind
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
            if case .overtime = state {
                actuals[index].status = .completed
            } else {
                actuals[index].status = .skipped
            }
        }
        state = .finished
    }

    mutating func extend(minutes: Int, at now: Date) throws(SessionError) {
        guard isAllowed(.extend) else { throw .notAllowed(.extend) }
        guard minutes > 0 else { throw .nonPositiveExtension }
        let extra = TimeInterval(minutes) * 60
        switch state {
        case let .running(index, endsAt):
            state = .running(segmentIndex: index, endsAt: endsAt.addingTimeInterval(extra))
        case let .paused(index, remaining):
            state = .paused(segmentIndex: index, remaining: remaining + extra)
        case let .overtime(index, _):
            closeOpenInterval(at: now)
            state = .running(segmentIndex: index, endsAt: now.addingTimeInterval(extra))
            openInterval = OpenInterval(kind: runningKind(of: index), start: now)
        case .idle, .finished:
            break
        }
    }

    /// Gives up on the current segment. Overtime counts as having finished it.
    mutating func skip(at now: Date) throws(SessionError) {
        guard isAllowed(.skip), let index = currentIndex else { throw .notAllowed(.skip) }
        if case .overtime = state {
            leave(segment: index, as: .completed, at: now)
        } else {
            leave(segment: index, as: .skipped, at: now)
        }
    }

    /// Leaves overtime and goes on to the next segment.
    mutating func advance(at now: Date) throws(SessionError) {
        guard isAllowed(.advance), let index = currentIndex else { throw .notAllowed(.advance) }
        leave(segment: index, as: .completed, at: now)
    }

    /// Plays out every segment that ran out before `now`: either by moving on by itself
    /// (auto-advance) or by waiting in overtime. Intervals get their real times.
    mutating func catchUp(to now: Date) {
        while case let .running(index, endsAt) = state, endsAt <= now {
            closeOpenInterval(at: endsAt)
            if autoAdvances(from: plan[index].kind) {
                leave(segment: index, as: .completed, at: endsAt)
            } else {
                state = .overtime(segmentIndex: index, since: endsAt)
                openInterval = OpenInterval(kind: runningKind(of: index), start: endsAt)
            }
        }
    }

    // MARK: Building blocks

    /// Starts `segment` running for its planned duration.
    mutating func begin(segment index: Int, at now: Date) {
        actuals[index].status = .active
        state = .running(segmentIndex: index, endsAt: now.addingTimeInterval(plan[index].duration))
        openInterval = OpenInterval(kind: runningKind(of: index), start: now)
    }

    /// Closes `index` with `status` and starts the next segment, or finishes the day after the last one.
    mutating func leave(segment index: Int, as status: SegmentStatus, at now: Date) {
        closeOpenInterval(at: now)
        actuals[index].status = status
        if index + 1 < plan.count {
            begin(segment: index + 1, at: now)
        } else {
            state = .finished
        }
    }

    /// Whether the end of a segment of `kind` moves on by itself.
    func autoAdvances(from kind: SegmentKind) -> Bool {
        kind == .work ? settings.autoAdvanceWorkToBreak : settings.autoAdvanceBreakToWork
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
