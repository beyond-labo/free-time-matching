import Foundation
import Testing
@testable import Himatch

@Suite("Prototype scenario")
struct HimatchPrototypeScenarioTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("参加OK回答がある募集だけを確定できる")
    func confirmationRequiresParticipantResponse() async throws {
        let scenario = HimatchPrototypeScenario(now: now)
        let client = scenario.client()
        let seeded = await client.load()

        let confirmed = try await client.confirmHosting(PrototypeIDs.hostingWithResponse)
        #expect(confirmed.hostings.first(where: { $0.id == PrototypeIDs.hostingWithResponse })?.status == .confirmed)
        #expect(confirmed.plans.count == 1)

        let created = try await client.createHosting(
            HostingDraft(
                mode: .online,
                area: nil,
                category: .game,
                start: seeded.availability[0].interval.start,
                duration: 60 * 60,
                friends: [seeded.friends[0]]
            )
        )
        let createdID = try #require(created.hostings.first?.id)
        await #expect(throws: PrototypeError.noParticipantResponse) {
            try await client.confirmHosting(createdID)
        }
    }

    @Test("ブロックは友達・募集・確定予定の投影を同時に更新する")
    func blockUpdatesCrossFeatureProjection() async throws {
        let scenario = HimatchPrototypeScenario(now: now)
        let client = scenario.client()
        _ = try await client.confirmHosting(PrototypeIDs.hostingWithResponse)

        let blocked = await client.block(PrototypeIDs.riku)

        #expect(!blocked.friends.contains(where: { $0.id == PrototypeIDs.riku }))
        #expect(blocked.blocked.contains(where: { $0.id == PrototypeIDs.riku }))
        #expect(blocked.hostings.allSatisfy { hosting in
            !hosting.friends.contains(where: { $0.id == PrototypeIDs.riku })
                && !hosting.participants.contains(where: { $0.friend.id == PrototypeIDs.riku })
        })
        #expect(blocked.plans.isEmpty)
    }

    @Test("削除受付時にアカウント関連のプロトタイプ投影を空にする")
    func deletionClearsAccountProjection() async {
        let scenario = HimatchPrototypeScenario(now: now)
        let deleted = await scenario.client().deleteAccount()

        #expect(deleted.availability.isEmpty)
        #expect(deleted.friends.isEmpty)
        #expect(deleted.requests.isEmpty)
        #expect(deleted.hostings.isEmpty)
        #expect(deleted.invitations.isEmpty)
        #expect(deleted.plans.isEmpty)
        if case let .accepted(reference) = deleted.deletionStatus {
            #expect(reference.hasPrefix("DEL-"))
        } else {
            Issue.record("削除受付状態ではありません")
        }
    }
}
