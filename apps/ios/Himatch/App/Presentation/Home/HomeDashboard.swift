import Foundation

/// Read-only projection of Home: which sections appear, in which order, and the notice count (2.1, 2.6).
/// Automatic proposals are the main path; inviting by hand is the secondary path below the user's own free time.
/// Built only from the user's own state; it never carries delivery counts, unanswered friends or declines (3.6).
struct HomeDashboard: Equatable {
    enum Section: Equatable {
        case friendRequests([FriendRequest])
        case proposals([SchedulingProposal], proposalsOff: Bool)
        case invitationsToAnswer([Hosting])
        case guide(FirstMatchStep, friendCount: Int)
        case confirmedPlans([SchedulingProposal])
        case myInvitations([Hosting])
        case availability([AvailabilitySlot], busyIDs: Set<UUID>)
        case timeCandidates([TimeCandidate])

        var kind: String {
            switch self {
            case .friendRequests: "friendRequests"
            case .proposals: "proposals"
            case .invitationsToAnswer: "invitationsToAnswer"
            case .guide: "guide"
            case .confirmedPlans: "confirmedPlans"
            case .myInvitations: "myInvitations"
            case .availability: "availability"
            case .timeCandidates: "timeCandidates"
            }
        }
    }

    enum PrimaryAction: Equatable {
        case inviteFriendCode
        case registerAvailability
    }

    var sections: [Section]
    var primaryAction: PrimaryAction
    var noticeCount: Int

    static func make(
        snapshot: AppSnapshot, scheduling: SchedulingSnapshot? = nil, record: FirstMatchRecord, now: Date, calendar: Calendar
    ) -> HomeDashboard {
        var sections: [Section] = []
        let incoming = snapshot.requests.filter { $0.direction == .incoming }
        if !incoming.isEmpty { sections.append(.friendRequests(incoming)) }

        let step = FirstMatchProgress.evaluate(snapshot: snapshot, scheduling: scheduling, record: record, now: now)
        let proposals = (scheduling?.proposals ?? [])
            .filter { $0.status == .pending && $0.end > now }
            .sorted { lhs, rhs in
                let l = lhs.myResponse == .pending, r = rhs.myResponse == .pending
                return l != r ? l : lhs.start < rhs.start
            }
        // While the guide explains preparation, it already says the proposals are off.
        let showsOff = !snapshot.friends.isEmpty && scheduling != nil && scheduling?.enabled == false && !isPreparing(step)
        if !proposals.isEmpty || showsOff { sections.append(.proposals(proposals, proposalsOff: showsOff)) }

        // Unanswered first, then answered or closed ones that are still relevant (7.1, 7.8, 7.9).
        let received = snapshot.invitations
            .filter { !$0.isHostedByMe && $0.candidateRange.end > now }
            .sorted { lhs, rhs in
                let l = needsAnswer(lhs, now: now), r = needsAnswer(rhs, now: now)
                return l != r ? l : lhs.candidateRange.start < rhs.candidateRange.start
            }
        if !received.isEmpty { sections.append(.invitationsToAnswer(received)) }

        if let step { sections.append(.guide(step, friendCount: snapshot.friends.count)) }

        let confirmed = (scheduling?.proposals ?? []).filter { $0.status == .confirmed && $0.end > now }.sorted { $0.start < $1.start }
        if !confirmed.isEmpty { sections.append(.confirmedPlans(confirmed)) }

        let ownOpen = snapshot.hostings.filter { $0.isHostedByMe && $0.status == .recruiting }
        if !ownOpen.isEmpty { sections.append(.myInvitations(ownOpen.sorted { $0.candidateRange.start < $1.candidateRange.start })) }

        // Always shown, so the first free time can be registered from Home even with no friends (2.1).
        let upcoming = snapshot.availability
            .filter { $0.interval.end > now }
            .sorted { $0.interval.start < $1.interval.start }
        let busy = Set(upcoming.filter { slot in ownOpen.contains { $0.candidateRange.overlaps(slot.interval) } }.map(\.id))
        sections.append(.availability(upcoming, busyIDs: busy))

        if !snapshot.friends.isEmpty {
            let candidates = TimeCandidatePolicy.candidates(
                now: now, calendar: calendar,
                availability: snapshot.availability,
                activeHostingRanges: ownOpen.map(\.candidateRange)
            )
            if !candidates.isEmpty { sections.append(.timeCandidates(candidates)) }
        }

        let unanswered = received.filter { needsAnswer($0, now: now) }.count
        let proposalsToAnswer = proposals.filter { $0.myResponse == .pending && $0.start > now }.count
        let unread = ParticipationNoticeDetector.newNotices(hostings: snapshot.hostings, seenKeys: record.seenParticipationKeys).count
        return HomeDashboard(
            sections: sections,
            primaryAction: snapshot.friends.isEmpty ? .inviteFriendCode : .registerAvailability,
            noticeCount: incoming.count + proposalsToAnswer + unanswered + unread
        )
    }

    static func needsAnswer(_ invitation: Hosting, now: Date) -> Bool {
        invitation.status == .recruiting && now < invitation.answerDeadline
            && (invitation.myInvitation?.status ?? .pending) == .pending
    }

    private static func isPreparing(_ step: FirstMatchStep?) -> Bool {
        if case .prepareProposals = step { return true }
        return false
    }
}
