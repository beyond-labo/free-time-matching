import Foundation

enum HostingMode: String, CaseIterable, Codable, Equatable, Sendable {
    case online = "オンライン"
    case offline = "オフライン"
}

enum HostingArea: String, CaseIterable, Codable, Equatable, Sendable {
    case shinjuku = "新宿"
    case shibuya = "渋谷"
    case discussLater = "あとで相談"
}

enum HostingStatus: String, Codable, Equatable, Sendable {
    case recruiting
    case confirmed
    case cancelled
    case expired
}

struct Participation: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var friend: FriendProfile
    var approvedIntervals: [TimeIntervalRange]
}

struct Hosting: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var mode: HostingMode
    var area: HostingArea?
    var category: ActivityCategory?
    var candidateRange: TimeIntervalRange
    var requiredDuration: TimeInterval
    var friends: [FriendProfile]
    var participants: [Participation]
    var status: HostingStatus
    /// Optimistic concurrency version returned by the hosting API.
    var version: Int = 1
    /// Present only in the invitee projection; declined and pending details are never exposed to a host.
    var myInvitation: HostingInvitation? = nil
    var isHostedByMe: Bool = true
    var host: FriendProfile? = nil

    /// Invitees must answer before the candidate interval begins.
    var answerDeadline: Date { candidateRange.start }
}

/// The recipient starts with a valid 15-minute preview, but must explicitly confirm it before accepting.
struct InvitationResponseSelection: Equatable, Sendable {
    let candidateRange: TimeIntervalRange
    private(set) var range: TimeIntervalRange
    private(set) var isConfirmed = false

    init(candidateRange: TimeIntervalRange) {
        self.candidateRange = candidateRange
        self.range = TimeIntervalRange(
            start: candidateRange.start,
            end: min(candidateRange.end, candidateRange.start.addingTimeInterval(15 * 60))
        )
    }

    func canStepStart(by quarters: Int) -> Bool {
        let start = range.start.addingTimeInterval(Double(quarters) * 15 * 60)
        return start >= candidateRange.start && start <= range.end.addingTimeInterval(-15 * 60)
    }

    func canStepEnd(by quarters: Int) -> Bool {
        let end = range.end.addingTimeInterval(Double(quarters) * 15 * 60)
        return end <= candidateRange.end && end >= range.start.addingTimeInterval(15 * 60)
    }

    mutating func stepStart(by quarters: Int) {
        guard canStepStart(by: quarters) else { return }
        range = TimeIntervalRange(
            start: range.start.addingTimeInterval(Double(quarters) * 15 * 60),
            end: range.end
        )
        isConfirmed = false
    }

    mutating func stepEnd(by quarters: Int) {
        guard canStepEnd(by: quarters) else { return }
        range = TimeIntervalRange(
            start: range.start,
            end: range.end.addingTimeInterval(Double(quarters) * 15 * 60)
        )
        isConfirmed = false
    }

    mutating func confirm() { isConfirmed = true }
}

struct HostingInvitation: Equatable, Codable, Sendable {
    enum Status: String, Codable, Sendable { case pending, accepted, declined }
    var status: Status
    var version: Int
    var intervals: [TimeIntervalRange]?
}

struct ConfirmedPlan: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var hostingID: UUID
    var interval: TimeIntervalRange
    var category: ActivityCategory?
    var mode: HostingMode
    var participants: [FriendProfile]
}

enum HostingPolicy {
    static func commonCandidates(
        host: [TimeIntervalRange],
        responses: [[TimeIntervalRange]],
        requiredDuration: TimeInterval
    ) -> [TimeIntervalRange] {
        responses.reduce(host) { partial, response in
            partial.flatMap { base in response.compactMap { base.intersection($0) } }
        }
        .filter { $0.duration >= requiredDuration }
        .sorted { $0.start < $1.start }
    }
}
