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
