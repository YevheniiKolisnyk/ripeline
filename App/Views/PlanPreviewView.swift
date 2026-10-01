import RipelineCore
import SwiftUI

/// The right half of the setup window: what the plan adds up to, notices, and the segment list.
struct PlanPreviewView: View {
    let result: DaySetupResult
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("setup.fromNow")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch result {
            case let .invalid(issue):
                Label(SetupText.message(for: issue), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
            case let .ready(_, preview, notices):
                summary(preview)
                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                    Label(SetupText.message(for: notice, locale: locale), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(preview.segments) { row($0) }
                    }
                }
            }
        }
        .padding(16)
    }

    private func summary(_ preview: DayPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("summary.focus") { Text(verbatim: SetupText.duration(preview.focus, locale: locale)) }
            LabeledContent("summary.rest") { Text(verbatim: SetupText.duration(preview.rest, locale: locale)) }
            LabeledContent("summary.ends") { Text(verbatim: time(preview.endsAt)) }
            if preview.freeRemainder >= 60 {
                LabeledContent("summary.free") { Text(verbatim: SetupText.duration(preview.freeRemainder, locale: locale)) }
            }
        }
        .font(.headline)
    }

    private func time(_ date: Date) -> String {
        SetupText.time(date, locale: locale, timeZone: .autoupdatingCurrent)
    }

    private func row(_ segment: PlannedSegment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: segment.kind == .work ? "timer" : "cup.and.saucer.fill")
                .frame(width: 20)
                .foregroundStyle(segment.kind == .work ? Color.accentColor : .secondary)
            Text(verbatim: "\(time(segment.start))–\(time(segment.end))").monospacedDigit()
            Text(verbatim: SetupText.kindName(segment.kind))
            Spacer()
            Text(verbatim: SetupText.duration(segment.duration, locale: locale)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(segment.kind == .longBreak ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SetupText.segmentLabel(segment, locale: locale, timeZone: .autoupdatingCurrent))
    }
}
