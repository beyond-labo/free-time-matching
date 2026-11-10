import Foundation

#if DEBUG
actor HimatchPrototypeScenario {
    private var state: AppSnapshot
    private var scheduling = SchedulingSnapshot.empty
    private var reportSequence = 1000

    /// Demo starting states. `showcase` keeps the original fixture used by the integration tests and previews.
    enum Seed: Sendable {
        case showcase
        case noFriends
        case withFriends
    }

    init(now: Date = Date(), seed: Seed = .showcase) {
        state = Self.seed(now: now, kind: seed)
    }

    nonisolated func client() -> HimatchClient {
        HimatchClient(
            load: { await self.snapshot() },
            loadAvailability: { await self.snapshot().availability },
            saveProfile: { try await self.saveProfile(name: $0, icon: $1) },
            addAvailability: { try await self.addAvailability($0) },
            removeAvailability: { await self.removeAvailability($0) },
            subtractAvailability: { range, _ in await self.subtractAvailability(range) },
            loadHostings: { let value = await self.snapshot(); return (value.hostings, value.invitations) },
            createHosting: { try await self.createHosting($0) },
            respondInvitation: { id, status, intervals, _, _ in
                try await self.respondInvitation(id: id, status: status, intervals: intervals)
            },
            cancelHosting: { id, _, _ in try await self.cancelHosting(id: id) },
            confirmHosting: { try await self.confirmHosting(id: $0) },
            acceptRequest: { await self.acceptRequest(id: $0) },
            removeFriend: { await self.removeFriend(id: $0) },
            submitReport: { try await self.submitReport(reason: $0, note: $1) },
            block: { await self.block(id: $0) },
            deleteAccount: { await self.deleteAccount() }
        )
    }

    func snapshot() -> AppSnapshot { state }

    func reset(now: Date = Date(), seed: Seed = .showcase) {
        scheduling = .empty
        demoProposalPeers = [:]
        state = Self.seed(now: now, kind: seed)
        reportSequence = 1000
    }

    private func saveProfile(name: String, icon: String) throws -> AppSnapshot {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(normalized.count) else { throw PrototypeError.invalidDisplayName }
        state.profileName = normalized
        state.profileIcon = icon
        return state
    }

    private func addAvailability(_ slot: AvailabilitySlot) throws -> AppSnapshot {
        var lower = slot.interval.start
        var upper = slot.interval.end
        var included = Set<UUID>()
        var changed = true
        while changed {
            changed = false
            for existing in state.availability where !included.contains(existing.id) {
                if existing.interval.start <= upper && lower <= existing.interval.end {
                    included.insert(existing.id)
                    lower = min(lower, existing.interval.start)
                    upper = max(upper, existing.interval.end)
                    changed = true
                }
            }
        }
        let remaining = state.availability.filter { !included.contains($0.id) }
        try AvailabilityPolicy.validate(slot, now: Date().addingTimeInterval(-60), existing: remaining)
        state.availability = remaining + [AvailabilitySlot(
            id: slot.id,
            interval: TimeIntervalRange(id: slot.id, start: lower, end: upper),
            category: slot.category,
            visibility: slot.visibility
        )]
        state.availability.sort { $0.interval.start < $1.interval.start }
        return state
    }

    private func removeAvailability(_ id: UUID) -> AppSnapshot {
        state.availability.removeAll { $0.id == id }
        return state
    }

    private func subtractAvailability(_ range: TimeIntervalRange) -> AppSnapshot {
        var result: [AvailabilitySlot] = []
        for slot in state.availability {
            guard slot.interval.overlaps(range) else { result.append(slot); continue }
            if slot.interval.start < range.start {
                result.append(AvailabilitySlot(interval: TimeIntervalRange(start: slot.interval.start, end: range.start), category: slot.category, visibility: slot.visibility))
            }
            if range.end < slot.interval.end {
                result.append(AvailabilitySlot(interval: TimeIntervalRange(start: range.end, end: slot.interval.end), category: slot.category, visibility: slot.visibility))
            }
        }
        state.availability = result.sorted { $0.interval.start < $1.interval.start }
        return state
    }

    private func createHosting(_ draft: HostingDraft) throws -> AppSnapshot {
        guard !draft.friends.isEmpty else { throw PrototypeError.friendRequired }
        if draft.mode == .offline, draft.area == nil { throw PrototypeError.areaRequired }
        let hosting = Hosting(
            id: UUID(),
            mode: draft.mode,
            area: draft.mode == .offline ? draft.area : nil,
            category: draft.category,
            candidateRange: TimeIntervalRange(start: draft.start, end: draft.start.addingTimeInterval(draft.duration)),
            requiredDuration: draft.duration,
            friends: draft.friends,
            participants: [],
            status: .recruiting
        )
        state.hostings.insert(hosting, at: 0)
        mergeHostAvailability(hosting.candidateRange, metadata: draft.availabilityMetadata)
        return state
    }

    /// Mirrors the backend: the candidate range is OR-registered into the host's own availability (ios-hosting 1.4).
    private func mergeHostAvailability(_ range: TimeIntervalRange, metadata: HostingAvailabilityMetadata?) {
        var lower = range.start
        var upper = range.end
        var included = Set<UUID>()
        var changed = true
        while changed {
            changed = false
            for slot in state.availability where !included.contains(slot.id) && slot.interval.start <= upper && lower <= slot.interval.end {
                included.insert(slot.id)
                lower = min(lower, slot.interval.start)
                upper = max(upper, slot.interval.end)
                changed = true
            }
        }
        let id = UUID()
        state.availability = state.availability.filter { !included.contains($0.id) } + [AvailabilitySlot(
            id: id,
            interval: TimeIntervalRange(id: id, start: lower, end: upper),
            category: metadata?.category,
            visibility: metadata?.visibility ?? .privateUntilAccepted
        )]
        state.availability.sort { $0.interval.start < $1.interval.start }
    }

    private func acceptInvitation(id: UUID, interval: TimeIntervalRange) throws -> AppSnapshot {
        guard let index = state.invitations.firstIndex(where: { $0.id == id }) else {
            throw PrototypeError.notFound
        }
        let me = FriendProfile(id: PrototypeIDs.me, displayName: state.profileName, icon: state.profileIcon)
        state.invitations[index].participants = [Participation(id: UUID(), friend: me, approvedIntervals: [interval])]
        return state
    }

    private func respondInvitation(id: UUID, status: HostingInvitation.Status, intervals: [TimeIntervalRange]) throws -> AppSnapshot {
        guard let index = state.invitations.firstIndex(where: { $0.id == id }) else { throw PrototypeError.notFound }
        if status == .accepted, let interval = intervals.first {
            _ = try acceptInvitation(id: id, interval: interval)
        }
        state.invitations[index].myInvitation = HostingInvitation(status: status, version: (state.invitations[index].myInvitation?.version ?? 0) + 1, intervals: status == .accepted ? intervals : nil)
        state.invitations[index].isHostedByMe = false
        return state
    }

    private func cancelHosting(id: UUID) throws -> AppSnapshot {
        guard let index = state.hostings.firstIndex(where: { $0.id == id }) else { throw PrototypeError.notFound }
        state.hostings[index].status = .cancelled
        return state
    }

    private func confirmHosting(id: UUID) throws -> AppSnapshot {
        guard let index = state.hostings.firstIndex(where: { $0.id == id }) else { throw PrototypeError.notFound }
        guard let own = state.availability.first?.interval else { throw PrototypeError.noCommonTime }
        let hosting = state.hostings[index]
        guard !hosting.participants.isEmpty else { throw PrototypeError.noParticipantResponse }
        let responseIntervals = hosting.participants.map(\.approvedIntervals)
        let candidates = HostingPolicy.commonCandidates(
            host: [own],
            responses: responseIntervals,
            requiredDuration: hosting.requiredDuration
        )
        guard let interval = candidates.first else { throw PrototypeError.noCommonTime }
        state.hostings[index].status = .confirmed
        let participants = hosting.participants.isEmpty ? Array(hosting.friends.prefix(1)) : hosting.participants.map(\.friend)
        state.plans.append(
            ConfirmedPlan(
                id: UUID(),
                hostingID: id,
                interval: TimeIntervalRange(start: interval.start, end: interval.start.addingTimeInterval(hosting.requiredDuration)),
                category: hosting.category,
                mode: hosting.mode,
                participants: participants
            )
        )
        return state
    }

    private func acceptRequest(id: UUID) -> AppSnapshot {
        guard let request = state.requests.first(where: { $0.id == id }) else { return state }
        state.requests.removeAll { $0.id == id }
        if !state.friends.contains(where: { $0.id == request.person.id }) {
            state.friends.append(request.person)
        }
        return state
    }

    private func removeFriend(id: UUID) -> AppSnapshot {
        state.friends.removeAll { $0.id == id }
        return state
    }

    private func submitReport(reason: ReportReason, note: String) throws -> ReportReceipt {
        guard note.count <= 500 else { throw PrototypeError.noteTooLong }
        reportSequence += 1
        return ReportReceipt(reference: "HIM-\(reportSequence)")
    }

    private func block(id: UUID) -> AppSnapshot {
        if let friend = state.friends.first(where: { $0.id == id }) {
            state.blocked.append(friend)
        }
        state.friends.removeAll { $0.id == id }
        state.requests.removeAll { $0.person.id == id }
        state.hostings = state.hostings.map { hosting in
            var copy = hosting
            copy.friends.removeAll { $0.id == id }
            copy.participants.removeAll { $0.friend.id == id }
            return copy
        }
        state.plans.removeAll { $0.participants.contains(where: { $0.id == id }) }
        return state
    }

    private func deleteAccount() -> AppSnapshot {
        state.availability = []
        state.friends = []
        state.requests = []
        state.hostings = []
        state.invitations = []
        state.plans = []
        state.deletionStatus = .accepted(reference: "DEL-\(Int(Date().timeIntervalSince1970))")
        return state
    }

    /// DEBUG demo: a friend sends a request with the shared invite code (only while there are no friends).
    func simulateFriendRequest() -> AppSnapshot {
        let riku = FriendProfile(id: PrototypeIDs.riku, displayName: "りく", icon: "figure.run")
        guard state.friends.isEmpty, !state.requests.contains(where: { $0.person.id == riku.id }) else { return state }
        state.requests.append(FriendRequest(id: UUID(), person: riku, direction: .incoming))
        return state
    }

    /// DEBUG demo: accepting a friend request also connects the other demo friends so invitations can be tried.
    func connectDemoFriends() -> AppSnapshot {
        for friend in Self.demoFriends where !state.friends.contains(where: { $0.id == friend.id }) {
            state.friends.append(friend)
        }
        state.requests.removeAll()
        return state
    }

    /// DEBUG demo: the next invited friend without an answer accepts part of the host's open invitation.
    func simulateAcceptance(hostingID: UUID) -> AppSnapshot {
        guard let index = state.hostings.firstIndex(where: { $0.id == hostingID && $0.status == .recruiting }) else { return state }
        let hosting = state.hostings[index]
        guard let friend = hosting.friends.first(where: { candidate in
            !hosting.participants.contains { $0.friend.id == candidate.id }
        }) else { return state }
        let range = hosting.candidateRange
        let answered = hosting.participants.count
        let interval = ReplyChoicePolicy.presets(for: range).dropFirst(answered).first?.range
            ?? TimeIntervalRange(start: range.start, end: range.end)
        state.hostings[index].participants.append(
            Participation(id: UUID(), friend: friend, approvedIntervals: [TimeIntervalRange(start: interval.start, end: interval.end)])
        )
        state.hostings[index].version += 1
        return state
    }

    // MARK: DEBUG demo of automatic proposals (mirrors the backend contract, not its matching logic)

    func schedulingSnapshot() -> SchedulingSnapshot { scheduling }

    func executeScheduling(_ command: SchedulingCommand) throws -> SchedulingSnapshot {
        switch command {
        case let .settings(enabled):
            scheduling.enabled = enabled
            if !enabled { endPendingProposals(as: .cancelled) }
        case let .permission(friendID, enabled):
            scheduling.permissions.removeAll { $0.friendId == friendID }
            scheduling.permissions.append(SchedulingPermission(friendId: friendID, enabled: enabled))
        case let .response(id, response, share, version):
            guard let proposal = scheduling.proposals.first(where: { $0.id == id }), proposal.version == version,
                  proposal.status == .pending else { throw SchedulingFailure.conflict }
            let confirmed = response == .accepted && proposal.peerResponse == .accepted
            replaceProposal(proposal, status: response == .declined ? .declined : (confirmed ? .confirmed : .pending),
                            myResponse: response, shareAcceptance: share,
                            peer: confirmed ? demoPeer(for: proposal) : proposal.peer, peerResponse: proposal.peerResponse)
        case let .cancel(id, version):
            guard let proposal = scheduling.proposals.first(where: { $0.id == id }), proposal.version == version else { throw SchedulingFailure.conflict }
            replaceProposal(proposal, status: .cancelled, myResponse: proposal.myResponse, shareAcceptance: proposal.shareAcceptance,
                            peer: proposal.peer, peerResponse: proposal.peerResponse)
        case .feedback, .blockFriend, .blockProposal, .report, .reportFriend:
            break
        }
        return scheduling
    }

    /// DEBUG demo: the system found common free time with a permitted friend.
    func simulateProposal(now: Date = Date()) -> SchedulingSnapshot {
        guard scheduling.enabled,
              let friend = state.friends.first(where: { scheduling.permits($0.id) }),
              !scheduling.proposals.contains(where: { $0.status == .pending })
        else { return scheduling }
        let base = AvailabilityPolicy.nextQuarterHour(after: now).addingTimeInterval(26 * 60 * 60)
        scheduling.proposals.insert(SchedulingProposal(
            id: UUID(), start: base, end: base.addingTimeInterval(2 * 60 * 60), status: .pending, myResponse: .pending,
            version: 1, shareAcceptance: false, peer: nil, peerResponse: nil, feedback: nil
        ), at: 0)
        demoProposalPeers[scheduling.proposals[0].id] = friend
        return scheduling
    }

    /// DEBUG demo: the other person answers OK. With both OKs the plan is confirmed.
    func simulatePeerAcceptance(proposalID: UUID) -> SchedulingSnapshot {
        guard let proposal = scheduling.proposals.first(where: { $0.id == proposalID && $0.status == .pending }) else { return scheduling }
        let confirmed = proposal.myResponse == .accepted
        replaceProposal(proposal, status: confirmed ? .confirmed : .pending, myResponse: proposal.myResponse,
                        shareAcceptance: proposal.shareAcceptance, peer: confirmed ? demoPeer(for: proposal) : nil, peerResponse: .accepted)
        return scheduling
    }

    private var demoProposalPeers: [UUID: FriendProfile] = [:]

    private func demoPeer(for proposal: SchedulingProposal) -> SchedulingPeer? {
        demoProposalPeers[proposal.id].map { SchedulingPeer(userId: $0.id, nickname: $0.displayName, presetIconKey: $0.icon) }
    }

    private func endPendingProposals(as status: SchedulingProposal.Status) {
        for proposal in scheduling.proposals where proposal.status == .pending {
            replaceProposal(proposal, status: status, myResponse: proposal.myResponse, shareAcceptance: proposal.shareAcceptance,
                            peer: proposal.peer, peerResponse: proposal.peerResponse)
        }
    }

    private func replaceProposal(
        _ proposal: SchedulingProposal, status: SchedulingProposal.Status, myResponse: SchedulingProposal.Response,
        shareAcceptance: Bool, peer: SchedulingPeer?, peerResponse: SchedulingProposal.Response?
    ) {
        guard let index = scheduling.proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        scheduling.proposals[index] = SchedulingProposal(
            id: proposal.id, start: proposal.start, end: proposal.end, status: status, myResponse: myResponse,
            version: proposal.version + 1, shareAcceptance: shareAcceptance, peer: peer, peerResponse: peerResponse,
            feedback: proposal.feedback
        )
    }

    static let demoFriends = [
        FriendProfile(id: PrototypeIDs.riku, displayName: "りく", icon: "figure.run"),
        FriendProfile(id: PrototypeIDs.sakura, displayName: "さくら", icon: "leaf.fill"),
        FriendProfile(id: PrototypeIDs.yui, displayName: "ゆい", icon: "gamecontroller.fill"),
    ]

    private static func seed(now: Date, kind: Seed) -> AppSnapshot {
        let showcase = showcaseSeed(now: now)
        switch kind {
        case .showcase:
            return showcase
        case .noFriends:
            var snapshot = showcase
            snapshot.availability = []
            snapshot.friends = []
            snapshot.requests = []
            snapshot.hostings = []
            snapshot.invitations = []
            return snapshot
        case .withFriends:
            var snapshot = showcase
            snapshot.friends = demoFriends
            snapshot.requests = []
            snapshot.hostings = []
            snapshot.invitations = snapshot.invitations.map { invitation in
                var copy = invitation
                copy.isHostedByMe = false
                copy.host = demoFriends[0]
                copy.myInvitation = HostingInvitation(status: .pending, version: 1, intervals: nil)
                return copy
            }
            return snapshot
        }
    }

    private static func showcaseSeed(now: Date) -> AppSnapshot {
        let start = AvailabilityPolicy.nextQuarterHour(after: now).addingTimeInterval(24 * 60 * 60)
        let riku = FriendProfile(id: PrototypeIDs.riku, displayName: "りく", icon: "figure.run")
        let sakura = FriendProfile(id: PrototypeIDs.sakura, displayName: "さくら", icon: "leaf.fill")
        let yui = FriendProfile(id: PrototypeIDs.yui, displayName: "ゆい", icon: "gamecontroller.fill")
        let invitation = Hosting(
            id: PrototypeIDs.invitation,
            mode: .online,
            area: nil,
            category: .game,
            candidateRange: TimeIntervalRange(start: start, end: start.addingTimeInterval(3 * 60 * 60)),
            requiredDuration: 60 * 60,
            friends: [],
            participants: [],
            status: .recruiting
        )
        let hostingWithResponse = Hosting(
            id: PrototypeIDs.hostingWithResponse,
            mode: .offline,
            area: .discussLater,
            category: .meal,
            candidateRange: TimeIntervalRange(start: start, end: start.addingTimeInterval(3 * 60 * 60)),
            requiredDuration: 60 * 60,
            friends: [riku],
            participants: [
                Participation(
                    id: PrototypeIDs.rikuParticipation,
                    friend: riku,
                    approvedIntervals: [
                        TimeIntervalRange(
                            start: start.addingTimeInterval(30 * 60),
                            end: start.addingTimeInterval(2 * 60 * 60)
                        )
                    ]
                )
            ],
            status: .recruiting
        )
        return AppSnapshot(
            profileName: "ひまり",
            profileIcon: "sun.max.fill",
            inviteCode: InviteCode(value: "HIMA-DEMA-FRND-CXDE-2742", expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60)),
            availability: [
                AvailabilitySlot(
                    interval: TimeIntervalRange(start: start, end: start.addingTimeInterval(2 * 60 * 60)),
                    category: .game
                )
            ],
            friends: [riku, sakura],
            requests: [FriendRequest(id: UUID(), person: yui, direction: .incoming)],
            hostings: [hostingWithResponse],
            invitations: [invitation],
            plans: [],
            blocked: [],
            deletionStatus: .idle
        )
    }
}

enum PrototypeIDs {
    static let me = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let riku = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let sakura = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let yui = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let invitation = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    static let hostingWithResponse = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    static let rikuParticipation = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
}
#endif
