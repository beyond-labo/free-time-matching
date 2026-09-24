import Foundation

enum ActivityCategory: String, CaseIterable, Codable, Equatable, Sendable {
    case game = "ゲーム"
    case meal = "ご飯"
    case call = "通話"
    case work = "作業"
}

enum AvailabilityVisibility: String, CaseIterable, Codable, Equatable, Sendable {
    case privateUntilAccepted
    case shareOnHosting

    var title: String {
        switch self {
        case .privateUntilAccepted: "参加OKするまで非公開"
        case .shareOnHosting: "募集時に主催者へ共有"
        }
    }
}

struct TimeIntervalRange: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var start: Date
    var end: Date

    init(id: UUID = UUID(), start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func overlaps(_ other: Self) -> Bool {
        start < other.end && other.start < end
    }

    func intersection(_ other: Self) -> Self? {
        let lower = max(start, other.start)
        let upper = min(end, other.end)
        return lower < upper ? Self(start: lower, end: upper) : nil
    }
}

struct AvailabilitySlot: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var interval: TimeIntervalRange
    var category: ActivityCategory?
    var visibility: AvailabilityVisibility

    init(
        id: UUID = UUID(),
        interval: TimeIntervalRange,
        category: ActivityCategory? = nil,
        visibility: AvailabilityVisibility = .privateUntilAccepted
    ) {
        self.id = id
        self.interval = interval
        self.category = category
        self.visibility = visibility
    }
}

enum AvailabilityValidationError: Error, Equatable, Sendable {
    case invalidInterval
    case past
    case outsideWindow
    case notQuarterHour
    case overlap(UUID)
}

enum AvailabilityPolicy {
    static let quarterHour: TimeInterval = 15 * 60
    static let window: TimeInterval = 14 * 24 * 60 * 60
    static let defaultDuration: TimeInterval = 2 * 60 * 60

    static func isQuarterHourAligned(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
        return (components.minute ?? 0) % 15 == 0
            && (components.second ?? 0) == 0
            && (components.nanosecond ?? 0) == 0
    }

    /// Returns the quarter-hour boundary at or before `date`.
    static func floorToQuarterHour(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: date)
        let startOfMinute = calendar.date(from: components) ?? date
        let remainder = (components.minute ?? 0) % 15
        return calendar.date(byAdding: .minute, value: -remainder, to: startOfMinute) ?? startOfMinute
    }

    /// The latest quarter-hour end that stays inside the 14-day window.
    static func latestEnd(now: Date, calendar: Calendar = .current) -> Date {
        floorToQuarterHour(now.addingTimeInterval(window), calendar: calendar)
    }

    /// Builds the initial interval for a new slot. A timeline anchor is floored to its quarter hour;
    /// without an anchor (or when the anchor is already past) the slot starts at the next quarter hour.
    /// Returns nil when not even a 15-minute slot fits before the window ends.
    static func draftInterval(
        anchor: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> TimeIntervalRange? {
        let earliest = nextQuarterHour(after: now, calendar: calendar)
        let start = anchor.map { max(floorToQuarterHour($0, calendar: calendar), earliest) } ?? earliest
        let latest = latestEnd(now: now, calendar: calendar)
        guard start.addingTimeInterval(quarterHour) <= latest else { return nil }
        return TimeIntervalRange(start: start, end: min(start.addingTimeInterval(defaultDuration), latest))
    }

    static func nextQuarterHour(after date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 15
        let minutesToAdd = remainder == 0 ? 15 : 15 - remainder
        let minuteComponents = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute],
            from: date
        )
        let startOfMinute = calendar.date(from: minuteComponents) ?? date
        return calendar.date(byAdding: .minute, value: minutesToAdd, to: startOfMinute) ?? date
    }

    static func validate(
        _ slot: AvailabilitySlot,
        now: Date,
        existing: [AvailabilitySlot],
        calendar: Calendar = .current
    ) throws {
        guard slot.interval.start < slot.interval.end else { throw AvailabilityValidationError.invalidInterval }
        guard slot.interval.start >= now else { throw AvailabilityValidationError.past }
        guard slot.interval.end <= now.addingTimeInterval(window) else {
            throw AvailabilityValidationError.outsideWindow
        }
        guard isQuarterHourAligned(slot.interval.start, calendar: calendar),
              isQuarterHourAligned(slot.interval.end, calendar: calendar)
        else {
            throw AvailabilityValidationError.notQuarterHour
        }
        if let match = existing.first(where: { $0.id != slot.id && $0.interval.overlaps(slot.interval) }) {
            throw AvailabilityValidationError.overlap(match.id)
        }
    }
}
