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
        guard slot.interval.end <= now.addingTimeInterval(14 * 24 * 60 * 60) else {
            throw AvailabilityValidationError.outsideWindow
        }
        let startMinute = calendar.component(.minute, from: slot.interval.start)
        let endMinute = calendar.component(.minute, from: slot.interval.end)
        guard startMinute % 15 == 0, endMinute % 15 == 0 else {
            throw AvailabilityValidationError.notQuarterHour
        }
        if let match = existing.first(where: { $0.id != slot.id && $0.interval.overlaps(slot.interval) }) {
            throw AvailabilityValidationError.overlap(match.id)
        }
    }
}
