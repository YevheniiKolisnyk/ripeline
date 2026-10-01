import Foundation

/// What a notification is about.
enum SignalKind: Equatable, Sendable {
    case workEnded
    case breakEnded
    case dayFinished
}

/// The localized text of a notification.
struct SignalContent: Equatable {
    let title: String
    let body: String

    /// Looks the text up in `bundle`, so a test can ask for a specific language.
    init(kind: SignalKind, bundle: Bundle = .main) {
        let name: String
        switch kind {
        case .workEnded: name = "workEnded"
        case .breakEnded: name = "breakEnded"
        case .dayFinished: name = "dayFinished"
        }
        title = bundle.localizedString(forKey: "notification.\(name).title", value: nil, table: nil)
        body = bundle.localizedString(forKey: "notification.\(name).body", value: nil, table: nil)
    }
}

/// Tells the user, outside the app, that a segment ended.
@MainActor protocol Notifier: AnyObject {
    /// Asks the system for permission to show notifications. Safe to call repeatedly.
    func requestAuthorization() async

    /// Arranges one notification `interval` seconds from now, replacing any pending one.
    func schedule(_ kind: SignalKind, in interval: TimeInterval)

    /// Removes the pending notification, if any.
    func cancelPending()

    /// Shows a notification immediately.
    func deliverNow(_ kind: SignalKind)
}
