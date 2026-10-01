import Foundation

/// Formats timer readouts. Plain integer math, so the result is identical in every language.
enum TimerText {
    /// Time left, rounded up so `0:00` appears only when the segment actually ends.
    /// `1930` gives `32:10`; an hour or more gives `1:02:05`. Negative input counts as zero.
    static func countdown(_ seconds: TimeInterval) -> String {
        format(Int(max(0, seconds).rounded(.up)))
    }

    /// Time past the planned end, rounded down, with a leading `+`: `+2:15`.
    static func overtime(_ seconds: TimeInterval) -> String {
        "+" + format(Int(max(0, seconds).rounded(.down)))
    }

    private static func format(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = totalSeconds % 3600 / 60
        let seconds = totalSeconds % 60
        let tail = String(format: "%02d", seconds)
        if hours > 0 {
            return "\(hours):" + String(format: "%02d", minutes) + ":" + tail
        }
        return "\(minutes):" + tail
    }
}
