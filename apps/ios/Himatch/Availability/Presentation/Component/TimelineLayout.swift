import Foundation

/// Read-only item drawn on the home timeline. The App layer maps its own availability and
/// confirmed plans into this shape so the timeline does not depend on Hosting types.
struct HomeScheduleItem: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case availability(AvailabilityVisibility)
        case plan
    }

    let id: HomeTimelineFeature.State.Item
    var interval: TimeIntervalRange
    var title: String
    var systemImage: String
    var kind: Kind
    /// Extra lines for the detail sheet (e.g. plan participants).
    var notes: [String] = []
}

/// Portion of an item that falls on one displayed day, with its side-by-side lane.
struct TimelineSegment: Equatable, Identifiable, Sendable {
    let item: HomeScheduleItem
    let start: Date
    let end: Date
    var lane: Int
    var laneCount: Int

    var id: HomeTimelineFeature.State.Item { item.id }
    var continuesFromPreviousDay: Bool { start > item.interval.start }
    var continuesToNextDay: Bool { end < item.interval.end }
}

enum TimelineLayout {
    static let quartersPerHour = 4

    static func dayRange(for day: Date, calendar: Calendar) -> TimeIntervalRange {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return TimeIntervalRange(start: start, end: end)
    }

    /// Clips items to `day` (half-open) and assigns lanes so overlapping items sit side by side.
    static func segments(for items: [HomeScheduleItem], on day: Date, calendar: Calendar) -> [TimelineSegment] {
        let range = dayRange(for: day, calendar: calendar)
        var segments = items
            .compactMap { item -> TimelineSegment? in
                guard let clipped = item.interval.intersection(range) else { return nil }
                return TimelineSegment(item: item, start: clipped.start, end: clipped.end, lane: 0, laneCount: 1)
            }
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.end > rhs.end : lhs.start < rhs.start
            }

        var clusterStart = 0
        var clusterEnd = Date.distantPast
        var laneEnds: [Date] = []

        func closeCluster(upTo endIndex: Int) {
            guard clusterStart < endIndex else { return }
            for index in clusterStart..<endIndex { segments[index].laneCount = max(laneEnds.count, 1) }
        }

        for index in segments.indices {
            let segment = segments[index]
            if segment.start >= clusterEnd {
                closeCluster(upTo: index)
                clusterStart = index
                laneEnds = []
            }
            if let lane = laneEnds.firstIndex(where: { $0 <= segment.start }) {
                segments[index].lane = lane
                laneEnds[lane] = segment.end
            } else {
                segments[index].lane = laneEnds.count
                laneEnds.append(segment.end)
            }
            clusterEnd = max(clusterEnd, segment.end)
        }
        closeCluster(upTo: segments.count)
        return segments
    }

    /// Minutes between the start of the day and `date` in absolute time.
    static func minutes(from dayStart: Date, to date: Date) -> Double {
        date.timeIntervalSince(dayStart) / 60
    }

    static func yOffset(for date: Date, dayStart: Date, hourHeight: Double) -> Double {
        minutes(from: dayStart, to: date) / 60 * hourHeight
    }

    /// Absolute time under a vertical position in the day grid (inverse of `yOffset`).
    static func date(atY y: Double, dayStart: Date, hourHeight: Double) -> Date {
        guard hourHeight > 0 else { return dayStart }
        return dayStart.addingTimeInterval(y / hourHeight * 60 * 60)
    }

    /// Quarter (0...3) within an hour row for a tap at `y` points from the row top.
    static func quarter(forRowOffset y: Double, hourHeight: Double) -> Int {
        guard hourHeight > 0 else { return 0 }
        let quarter = Int((y / (hourHeight / Double(quartersPerHour))).rounded(.down))
        return min(max(quarter, 0), quartersPerHour - 1)
    }

    static func date(hour: Int, quarter: Int = 0, on day: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: hour * 60 + quarter * 15, to: dayStart) ?? dayStart
    }
}
