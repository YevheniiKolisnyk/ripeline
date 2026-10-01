import Foundation

/// What kind of session a snapshot holds.
public enum SessionKind: String, Codable, Sendable, Equatable {
    /// An ordinary day with a plan that is fixed once the day starts.
    case day
    /// A session started without planning a day. Its plan grows as blocks are added while it runs.
    case quick
}
