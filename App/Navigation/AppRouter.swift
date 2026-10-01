import Observation

/// The two tabs of the app's window.
enum WindowTab: Hashable, Sendable {
    case today
    case history
}

/// Which tab the window shows. Shared so the popover can open the window on the right one. It only
/// changes when the user or the popover changes it, never because a day started or ended.
@MainActor @Observable
final class AppRouter {
    var tab: WindowTab = .today
}
