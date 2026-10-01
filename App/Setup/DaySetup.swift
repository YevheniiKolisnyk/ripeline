import Foundation
import RipelineCore

/// Why a form cannot become a day. These block "Start".
enum DaySetupIssue: Equatable, Sendable {
    /// In "until time" mode the end time is not later than now.
    case endNotAfterNow
    /// The settings leave no room for even one block.
    case dayTooShort
    /// The generator refused the request. Cannot happen after normalization; kept so a refusal is
    /// never mistaken for a short day.
    case invalidInput
}

/// Things worth telling the user about a plan that can still start.
enum DaySetupNotice: Equatable, Sendable {
    /// A long break was requested but did not fit, so the plan has none.
    case longBreakNotPlaced
    /// Part of the day, in whole minutes, is left without a block.
    case remainderLeftFree(minutes: Int)
}

/// What the generated plan adds up to.
struct DayPreview: Equatable, Sendable {
    let segments: [PlannedSegment]
    /// Seconds of work and of breaks in the plan.
    let focus: TimeInterval
    let rest: TimeInterval
    /// The end of the last segment.
    let endsAt: Date
    /// Seconds between the end of the plan and the requested end of the day; zero in net-focus mode.
    let freeRemainder: TimeInterval
}

enum DaySetupResult: Equatable, Sendable {
    case ready(request: DayPlanRequest, preview: DayPreview, notices: [DaySetupNotice])
    case invalid(DaySetupIssue)
}

/// Turns what the user entered into a plan, as of a moment. The plan always starts at `now`.
enum DaySetup {
    static func evaluate(form: DayPlanForm, now: Date, calendar: Calendar) -> DaySetupResult {
        let form = form.normalized()

        let mode: DayPlanRequest.Mode
        var requestedEnd: Date?
        switch form.mode {
        case .untilTime:
            let end = form.endTime.date(on: now, calendar: calendar)
            guard end > now else { return .invalid(.endNotAfterNow) }
            mode = .untilTime(start: now, end: end)
            requestedEnd = end
        case .netFocus:
            mode = .netFocus(start: now, focusMinutes: form.focusMinutes)
        }

        let longBreak: DayPlanRequest.LongBreak
        switch form.longBreak {
        case .none: longBreak = .none
        case let .atTime(time): longBreak = .atTime(time.date(on: now, calendar: calendar))
        case let .afterBlock(block): longBreak = .afterWorkBlock(block)
        }

        let remainder: DayPlanRequest.RemainderStrategy
        switch form.remainder {
        case .shortBlock: remainder = .shortBlock(minMinutes: form.minBlockMinutes)
        case .leaveFree: remainder = .leaveFree
        case .stretchBlocks: remainder = .stretchBlocks
        }

        let request = DayPlanRequest(mode: mode, longBreak: longBreak, remainderStrategy: remainder, preset: form.preset)
        let plan: [PlannedSegment]
        do { plan = try PlanGenerator.generate(request) } catch { return .invalid(.invalidInput) }
        guard let last = plan.last else { return .invalid(.dayTooShort) }

        let preview = DayPreview(
            segments: plan,
            focus: plan.filter { $0.kind == .work }.reduce(0) { $0 + $1.duration },
            rest: plan.filter { $0.kind.isBreak }.reduce(0) { $0 + $1.duration },
            endsAt: last.end,
            freeRemainder: requestedEnd.map { max(0, $0.timeIntervalSince(last.end)) } ?? 0
        )

        var notices: [DaySetupNotice] = []
        if form.longBreak != .none, !plan.contains(where: { $0.kind == .longBreak }) {
            notices.append(.longBreakNotPlaced)
        }
        let freeMinutes = Int(preview.freeRemainder / 60)
        if freeMinutes >= 1 { notices.append(.remainderLeftFree(minutes: freeMinutes)) }
        return .ready(request: request, preview: preview, notices: notices)
    }
}
