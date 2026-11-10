import SwiftUI

extension AvailabilityFormatting {
    /// "今日 19:00〜22:00" / "明日 …" / "9月24日(木) …" for cards on Home and in sheets.
    static func friendlyRange(_ interval: TimeIntervalRange, calendar: Calendar, now: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: interval.start)).day ?? 0
        let label: String
        switch days {
        case 0: label = "今日"
        case 1: label = "明日"
        default: label = day(interval.start, calendar: calendar)
        }
        let start = time(interval.start, calendar: calendar)
        let end = time(interval.end, calendar: calendar)
        let overnight = !calendar.isDate(interval.start, inSameDayAs: interval.end)
        return "\(label) \(start)〜\(overnight ? "翌" : "")\(end)"
    }

    /// "今日 19:00" style moment, e.g. for answer deadlines.
    static func friendlyMoment(_ date: Date, calendar: Calendar, now: Date) -> String {
        friendlyRange(TimeIntervalRange(start: date, end: date), calendar: calendar, now: now)
            .components(separatedBy: "〜").first ?? time(date, calendar: calendar)
    }

    static func timeSpan(_ interval: TimeIntervalRange, calendar: Calendar) -> String {
        "\(time(interval.start, calendar: calendar))〜\(time(interval.end, calendar: calendar))"
    }
}

/// The candidate window as a bar with the answered (or selected) spans laid on top (6.3, 7.4, 8.2).
/// VoiceOver reads the same information as sentences (11.2).
struct CandidateTimeBar: View {
    let candidate: TimeIntervalRange
    var highlights: [TimeIntervalRange] = []
    var highlightTint: Color = HimatchColor.plan

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: HimatchRadius.block, style: .continuous)
                        .fill(HimatchColor.tint(HimatchColor.hosting))
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, span in
                        let start = fraction(span.start) * width
                        let end = fraction(span.end) * width
                        RoundedRectangle(cornerRadius: HimatchRadius.block - 3, style: .continuous)
                            .fill(highlightTint)
                            .frame(width: max(end - start, 6), height: 20)
                            .offset(x: start)
                    }
                }
            }
            .frame(height: 28)
            HStack {
                Text(AvailabilityFormatting.time(candidate.start, calendar: calendar))
                Spacer()
                Text(AvailabilityFormatting.time(candidate.end, calendar: calendar))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func fraction(_ date: Date) -> CGFloat {
        let total = candidate.duration
        guard total > 0 else { return 0 }
        return CGFloat(min(max(date.timeIntervalSince(candidate.start) / total, 0), 1))
    }

    private var accessibilityText: String {
        let base = "候補 \(AvailabilityFormatting.timeSpan(candidate, calendar: calendar))"
        guard !highlights.isEmpty else { return base }
        let spans = highlights.map { AvailabilityFormatting.timeSpan($0, calendar: calendar) }.joined(separator: "、")
        return "\(base)。選ばれている時間 \(spans)"
    }
}
