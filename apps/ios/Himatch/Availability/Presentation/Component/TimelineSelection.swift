import Foundation

/// Half-open `[start, end)` range picked directly on the day timeline.
/// Always quarter-hour aligned, inside one displayed day and at least 15 minutes long.
struct QuarterRange: Equatable, Hashable, Sendable {
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Adjustable invitation window that must stay within one registered availability interval.
struct AvailabilityInviteSelection: Equatable, Sendable {
    let availability: TimeIntervalRange
    private(set) var range: QuarterRange

    init(availability: TimeIntervalRange) {
        self.availability = availability
        self.range = QuarterRange(start: availability.start, end: availability.end)
    }

    func canStepStart(by quarters: Int) -> Bool {
        let proposed = range.start.addingTimeInterval(Double(quarters) * AvailabilityPolicy.quarterHour)
        return proposed >= availability.start && proposed <= range.end.addingTimeInterval(-AvailabilityPolicy.quarterHour)
    }

    func canStepEnd(by quarters: Int) -> Bool {
        let proposed = range.end.addingTimeInterval(Double(quarters) * AvailabilityPolicy.quarterHour)
        return proposed <= availability.end && proposed >= range.start.addingTimeInterval(AvailabilityPolicy.quarterHour)
    }

    mutating func stepStart(by quarters: Int) {
        guard canStepStart(by: quarters) else { return }
        range.start = range.start.addingTimeInterval(Double(quarters) * AvailabilityPolicy.quarterHour)
    }

    mutating func stepEnd(by quarters: Int) {
        guard canStepEnd(by: quarters) else { return }
        range.end = range.end.addingTimeInterval(Double(quarters) * AvailabilityPolicy.quarterHour)
    }
}

enum SelectionEdge: Hashable, Sendable {
    case start
    case end
}

/// Geometry rules for direct selection on one day. Registration rules (past, 14-day window,
/// overlap) are not decided here; they stay in `AvailabilityPolicy.validate`.
enum TimelineSelection {
    private static let quarter = AvailabilityPolicy.quarterHour

    /// The 15-minute slot containing `date`, kept inside the day of `day`.
    static func quarter(containing date: Date, day: Date, calendar: Calendar) -> QuarterRange {
        let start = quarterStart(for: date, day: day, calendar: calendar)
        return QuarterRange(start: start, end: start.addingTimeInterval(quarter))
    }

    /// Range covering the quarters under `anchor` and `focus`, regardless of drag direction.
    static func normalized(anchor: Date, focus: Date, day: Date, calendar: Calendar) -> QuarterRange {
        let anchorStart = quarterStart(for: anchor, day: day, calendar: calendar)
        let focusStart = quarterStart(for: focus, day: day, calendar: calendar)
        return QuarterRange(
            start: min(anchorStart, focusStart),
            end: max(anchorStart, focusStart).addingTimeInterval(quarter)
        )
    }

    /// Moves one edge by whole quarters, keeping at least 15 minutes inside the day.
    static func stepped(_ range: QuarterRange, edge: SelectionEdge, quarters: Int, calendar: Calendar) -> QuarterRange {
        let offset = Double(quarters) * quarter
        switch edge {
        case .start: return moving(range, edge: .start, to: range.start.addingTimeInterval(offset), calendar: calendar)
        case .end: return moving(range, edge: .end, to: range.end.addingTimeInterval(offset), calendar: calendar)
        }
    }

    /// Moves one edge to the quarter boundary nearest to `date` (used by the drag handles).
    static func dragged(_ range: QuarterRange, edge: SelectionEdge, to date: Date, calendar: Calendar) -> QuarterRange {
        let rounded = AvailabilityPolicy.floorToQuarterHour(date.addingTimeInterval(quarter / 2), calendar: calendar)
        return moving(range, edge: edge, to: rounded, calendar: calendar)
    }

    private static func moving(_ range: QuarterRange, edge: SelectionEdge, to boundary: Date, calendar: Calendar) -> QuarterRange {
        let day = TimelineLayout.dayRange(for: range.start, calendar: calendar)
        var result = range
        switch edge {
        case .start:
            result.start = min(max(boundary, day.start), range.end.addingTimeInterval(-quarter))
        case .end:
            result.end = max(min(boundary, day.end), range.start.addingTimeInterval(quarter))
        }
        return result
    }

    private static func quarterStart(for date: Date, day: Date, calendar: Calendar) -> Date {
        let range = TimelineLayout.dayRange(for: day, calendar: calendar)
        let floored = AvailabilityPolicy.floorToQuarterHour(date, calendar: calendar)
        return min(max(floored, range.start), range.end.addingTimeInterval(-quarter))
    }
}
