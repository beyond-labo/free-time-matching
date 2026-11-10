import Foundation

/// Explicit metadata for the host's own availability, independent of the event category.
struct HostingAvailabilityMetadata: Equatable, Codable, Sendable {
    var category: ActivityCategory?
    var visibility: AvailabilityVisibility
}

enum HostingMode: String, CaseIterable, Codable, Equatable, Sendable {
    case online = "オンライン"
    case offline = "オフライン"

    /// User-facing name (「会い方」). The raw value stays stable for persistence and adapters.
    var displayName: String {
        switch self {
        case .online: "オンライン"
        case .offline: "会う"
        }
    }
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

    /// With two or more 参加OK, the first window where the candidate and every participant overlap (requirement 8.3).
    static func everyoneAvailable(candidate: TimeIntervalRange, participants: [Participation]) -> TimeIntervalRange? {
        guard participants.count >= 2 else { return nil }
        return commonCandidates(
            host: [candidate],
            responses: participants.map(\.approvedIntervals),
            requiredDuration: AvailabilityPolicy.quarterHour
        ).first
    }
}
