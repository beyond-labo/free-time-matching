import Foundation

/// A participant answer the host has not been shown yet (requirement 8.1).
struct ParticipationNotice: Equatable, Sendable {
    var hostingID: UUID
    var friend: FriendProfile
    var interval: TimeIntervalRange
    var isChange: Bool
}

/// Detects new or changed 参加OK on the host's open invitations by comparing against locally seen keys.
/// Keys are built from identifiers and epoch seconds only, never from names or formatted times.
enum ParticipationNoticeDetector {
    static func key(hostingID: UUID, participationID: UUID, intervals: [TimeIntervalRange]) -> String {
        let spans = intervals
            .map { "\(Int($0.start.timeIntervalSince1970))-\(Int($0.end.timeIntervalSince1970))" }
            .joined(separator: ",")
        return "\(hostingID.uuidString)|\(participationID.uuidString)|\(spans)"
    }

    private static func participantPrefix(hostingID: UUID, participationID: UUID) -> String {
        "\(hostingID.uuidString)|\(participationID.uuidString)|"
    }

    private static func openOwnHostings(_ hostings: [Hosting]) -> [Hosting] {
        hostings.filter { $0.isHostedByMe && $0.status == .recruiting }
    }

    static func newNotices(hostings: [Hosting], seenKeys: Set<String>) -> [ParticipationNotice] {
        openOwnHostings(hostings).flatMap { hosting in
            hosting.participants.compactMap { participation -> ParticipationNotice? in
                let current = key(hostingID: hosting.id, participationID: participation.id, intervals: participation.approvedIntervals)
                guard !seenKeys.contains(current), let interval = participation.approvedIntervals.first else { return nil }
                let prefix = participantPrefix(hostingID: hosting.id, participationID: participation.id)
                return ParticipationNotice(
                    hostingID: hosting.id,
                    friend: participation.friend,
                    interval: interval,
                    isChange: seenKeys.contains { $0.hasPrefix(prefix) }
                )
            }
        }
    }

    static func activeKeys(hostings: [Hosting]) -> Set<String> {
        Set(openOwnHostings(hostings).flatMap { hosting in
            hosting.participants.map {
                key(hostingID: hosting.id, participationID: $0.id, intervals: $0.approvedIntervals)
            }
        })
    }
}
