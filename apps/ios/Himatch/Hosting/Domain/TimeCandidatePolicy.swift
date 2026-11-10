import Foundation

/// A ready-made invitation window offered on Home and in the invitation composer.
struct TimeCandidate: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case tonight
        case tomorrowNight
        case saturdayAfternoon
        case availability(UUID)
    }

    var kind: Kind
    var range: TimeIntervalRange

    var id: String {
        switch kind {
        case .tonight: "tonight"
        case .tomorrowNight: "tomorrowNight"
        case .saturdayAfternoon: "saturdayAfternoon"
        case let .availability(id): "availability-\(id.uuidString)"
        }
    }

    var title: String {
        switch kind {
        case .tonight: "今夜"
        case .tomorrowNight: "明日の夜"
        case .saturdayAfternoon: "土曜の午後"
        case .availability: "あなたの暇"
        }
    }
}

/// Builds time candidates in local time and returns absolute instants (requirements 4.1–4.3).
enum TimeCandidatePolicy {
    static let minimumRemaining: TimeInterval = 60 * 60
    static let maximumAvailabilityCandidates = 2

    static func candidates(
        now: Date,
        calendar: Calendar,
        availability: [AvailabilitySlot],
        activeHostingRanges: [TimeIntervalRange]
    ) -> [TimeCandidate] {
        let today = calendar.startOfDay(for: now)
        var result: [TimeCandidate] = []

        func fixed(_ kind: TimeCandidate.Kind, dayOffset: Int, startHour: Int, endHour: Int) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day),
                  let range = clamp(TimeIntervalRange(start: start, end: end), now: now, calendar: calendar)
            else { return }
            guard !result.contains(where: { $0.range.start == range.start && $0.range.end == range.end }) else { return }
            result.append(TimeCandidate(kind: kind, range: range))
        }

        fixed(.tonight, dayOffset: 0, startHour: 19, endHour: 22)
        fixed(.tomorrowNight, dayOffset: 1, startHour: 19, endHour: 22)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday, 7 = Saturday
        fixed(.saturdayAfternoon, dayOffset: (7 - weekday + 7) % 7, startHour: 13, endHour: 17)

        let availabilityCandidates = availability
            .sorted { $0.interval.start < $1.interval.start }
            .filter { slot in !activeHostingRanges.contains { $0.overlaps(slot.interval) } }
            .compactMap { slot -> TimeCandidate? in
                clamp(slot.interval, now: now, calendar: calendar).map {
                    TimeCandidate(kind: .availability(slot.id), range: $0)
                }
            }
            .prefix(maximumAvailabilityCandidates)
        result.append(contentsOf: availabilityCandidates)
        return result
    }

    /// Moves a past start to the next quarter hour and drops candidates that are too short or outside the window.
    static func clamp(_ range: TimeIntervalRange, now: Date, calendar: Calendar) -> TimeIntervalRange? {
        let earliest = AvailabilityPolicy.nextQuarterHour(after: now, calendar: calendar)
        let start = range.start < earliest ? earliest : range.start
        let end = min(range.end, AvailabilityPolicy.latestEnd(now: now, calendar: calendar))
        guard end.timeIntervalSince(start) >= minimumRemaining else { return nil }
        return TimeIntervalRange(id: range.id, start: start, end: end)
    }
}
