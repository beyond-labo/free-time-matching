import Foundation

actor HimatchPrototypeScenario {
    private var state: AppSnapshot
    private var reportSequence = 1000

    init(now: Date = Date()) {
        state = Self.seed(now: now)
    }

    nonisolated func client() -> HimatchClient {
        HimatchClient(
            load: { await self.snapshot() },
            saveProfile: { try await self.saveProfile(name: $0, icon: $1) },
            addAvailability: { try await self.addAvailability($0) },
            removeAvailability: { await self.removeAvailability($0) },
            createHosting: { try await self.createHosting($0) },
            acceptInvitation: { try await self.acceptInvitation(id: $0, interval: $1) },
            confirmHosting: { try await self.confirmHosting(id: $0) },
            acceptRequest: { await self.acceptRequest(id: $0) },
            removeFriend: { await self.removeFriend(id: $0) },
            submitReport: { try await self.submitReport(reason: $0, note: $1) },
            block: { await self.block(id: $0) },
            deleteAccount: { await self.deleteAccount() }
        )
    }

    func snapshot() -> AppSnapshot { state }

    func reset(now: Date = Date()) {
        state = Self.seed(now: now)
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
        try AvailabilityPolicy.validate(slot, now: Date().addingTimeInterval(-60), existing: state.availability)
        state.availability.append(slot)
        state.availability.sort { $0.interval.start < $1.interval.start }
        return state
    }

    private func removeAvailability(_ id: UUID) -> AppSnapshot {
        state.availability.removeAll { $0.id == id }
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
            candidateRange: TimeIntervalRange(start: draft.start, end: draft.start.addingTimeInterval(3 * 60 * 60)),
            requiredDuration: draft.duration,
            friends: draft.friends,
            participants: [],
            status: .recruiting
        )
        state.hostings.insert(hosting, at: 0)
        return state
    }

    private func acceptInvitation(id: UUID, interval: TimeIntervalRange) throws -> AppSnapshot {
        guard let index = state.invitations.firstIndex(where: { $0.id == id }) else {
            throw PrototypeError.notFound
        }
        let me = FriendProfile(id: PrototypeIDs.me, displayName: state.profileName, icon: state.profileIcon)
        state.invitations[index].participants = [Participation(id: UUID(), friend: me, approvedIntervals: [interval])]
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

    private static func seed(now: Date) -> AppSnapshot {
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
            inviteCode: InviteCode(value: "HIMA-2741", expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60)),
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

enum PrototypeError: LocalizedError, Equatable, Sendable {
    case invalidDisplayName
    case friendRequired
    case areaRequired
    case noCommonTime
    case noParticipantResponse
    case notFound
    case noteTooLong

    var errorDescription: String? {
        switch self {
        case .invalidDisplayName: "表示名は1〜20文字で入力してください。"
        case .friendRequired: "友達を1人以上選んでください。"
        case .areaRequired: "オフラインではエリアを選んでください。"
        case .noCommonTime: "全員が参加できる時間がまだありません。"
        case .noParticipantResponse: "参加OKの回答がまだありません。"
        case .notFound: "最新の状態を取得できませんでした。"
        case .noteTooLong: "補足は500文字以内で入力してください。"
        }
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
