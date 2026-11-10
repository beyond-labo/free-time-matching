import Foundation

/// What the user has prepared for automatic proposals (requirement 3.2). Only the user's own settings.
struct FirstMatchReadiness: Equatable, Sendable {
    var hasAvailability: Bool
    var proposalsEnabled: Bool
    var hasPermittedFriend: Bool
    var isReady: Bool { hasAvailability && proposalsEnabled && hasPermittedFriend }
}

/// The step of the 「はじめての予定」 guide shown on Home (requirement 3).
/// Automatic proposals are the main path; inviting by hand stays available outside the guide.
enum FirstMatchStep: Equatable, Sendable {
    case connectFriends(codeShared: Bool)
    case prepareProposals(FirstMatchReadiness)
    case answerProposal(hasPendingProposal: Bool)

    /// Number of completed steps out of three.
    var completedCount: Int {
        switch self {
        case .connectFriends: 0
        case .prepareProposals: 1
        case .answerProposal: 2
        }
    }
}

/// Per-account record kept on the device. Holds no names or times.
struct FirstMatchRecord: Equatable, Codable, Sendable {
    enum Guide: String, Codable, Sendable {
        case active
        case completed
        case dismissed
    }

    var guide: Guide = .active
    var inviteCodeShared = false
    var lastMeeting: LastMeeting?
    var seenParticipationKeys: Set<String> = []
}

struct LastMeeting: Equatable, Codable, Sendable {
    var mode: HostingMode
    var area: HostingArea?
}

enum FirstMatchProgress {
    /// nil means the guide is not shown. `scheduling` is nil until the automatic-proposal state is loaded.
    static func evaluate(snapshot: AppSnapshot, scheduling: SchedulingSnapshot?, record: FirstMatchRecord, now: Date) -> FirstMatchStep? {
        guard record.guide == .active, !isCompleted(snapshot: snapshot, scheduling: scheduling) else { return nil }
        if snapshot.friends.isEmpty { return .connectFriends(codeShared: record.inviteCodeShared) }
        let readiness = readiness(snapshot: snapshot, scheduling: scheduling, now: now)
        guard readiness.isReady else { return .prepareProposals(readiness) }
        let hasPending = scheduling?.proposals.contains { $0.status == .pending && $0.myResponse == .pending && $0.start > now } ?? false
        return .answerProposal(hasPendingProposal: hasPending)
    }

    static func readiness(snapshot: AppSnapshot, scheduling: SchedulingSnapshot?, now: Date) -> FirstMatchReadiness {
        FirstMatchReadiness(
            hasAvailability: snapshot.availability.contains { $0.interval.end > now },
            proposalsEnabled: scheduling?.enabled ?? false,
            hasPermittedFriend: snapshot.friends.contains { scheduling?.permits($0.id) ?? false }
        )
    }

    /// True once a plan is confirmed from a proposal, or a 参加OK was exchanged through a hand-made invitation.
    static func isCompleted(snapshot: AppSnapshot, scheduling: SchedulingSnapshot?) -> Bool {
        (scheduling?.proposals.contains { $0.status == .confirmed } ?? false)
            || snapshot.hostings.contains { $0.isHostedByMe && !$0.participants.isEmpty }
            || snapshot.invitations.contains { $0.myInvitation?.status == .accepted }
    }
}
