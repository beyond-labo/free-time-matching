import Foundation

/// How an invitee picks the part of the candidate window they can join (requirements 7.2, 7.3).
enum ReplyChoice: Equatable, Hashable, Sendable {
    case whole
    case firstHalf
    case secondHalf
    case custom

    var title: String {
        switch self {
        case .whole: "全部"
        case .firstHalf: "前半"
        case .secondHalf: "後半"
        case .custom: "時間を指定"
        }
    }
}

enum ReplyChoicePolicy {
    static let halvesThreshold: TimeInterval = 2 * 60 * 60
    private static let quarter = AvailabilityPolicy.quarterHour

    static func presets(for candidate: TimeIntervalRange) -> [(choice: ReplyChoice, range: TimeIntervalRange)] {
        var result: [(ReplyChoice, TimeIntervalRange)] = [(.whole, TimeIntervalRange(start: candidate.start, end: candidate.end))]
        if candidate.duration >= halvesThreshold {
            let mid = midpoint(of: candidate)
            result.append((.firstHalf, TimeIntervalRange(start: candidate.start, end: mid)))
            result.append((.secondHalf, TimeIntervalRange(start: mid, end: candidate.end)))
        }
        return result
    }

    /// Splits the window on a 15-minute boundary counted from the candidate start.
    static func midpoint(of candidate: TimeIntervalRange) -> Date {
        let quarters = (candidate.duration / quarter / 2).rounded()
        return candidate.start.addingTimeInterval(quarters * quarter)
    }

    static func customStarts(in candidate: TimeIntervalRange) -> [Date] {
        stride(from: candidate.start, to: candidate.end, by: quarter).map { $0 }
    }

    static func customEnds(in candidate: TimeIntervalRange, after start: Date) -> [Date] {
        guard start >= candidate.start, start < candidate.end else { return [] }
        return stride(from: start.addingTimeInterval(quarter), through: candidate.end, by: quarter).map { $0 }
    }

    static func range(for choice: ReplyChoice, candidate: TimeIntervalRange, custom: TimeIntervalRange) -> TimeIntervalRange? {
        if choice == .custom {
            return isValidCustom(custom, in: candidate) ? custom : nil
        }
        return presets(for: candidate).first { $0.choice == choice }?.range
    }

    static func isValidCustom(_ range: TimeIntervalRange, in candidate: TimeIntervalRange) -> Bool {
        range.start >= candidate.start && range.end <= candidate.end && range.start < range.end
            && range.start.timeIntervalSince(candidate.start).truncatingRemainder(dividingBy: quarter) == 0
            && range.end.timeIntervalSince(candidate.start).truncatingRemainder(dividingBy: quarter) == 0
    }
}
