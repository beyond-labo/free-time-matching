import Foundation
import Testing
@testable import Himatch

@Suite("Hosting policy")
struct HostingPolicyTests {
    @Test("必要時間を満たす共通候補だけを返す")
    func commonCandidatesKeepOnlyRequiredDuration() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let host = [TimeIntervalRange(start: start, end: start.addingTimeInterval(10_800))]
        let first = [TimeIntervalRange(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(7200))]
        let second = [TimeIntervalRange(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(9000))]

        let result = HostingPolicy.commonCandidates(host: host, responses: [first, second], requiredDuration: 3600)

        #expect(result.count == 1)
        #expect(result[0].start == start.addingTimeInterval(3600))
        #expect(result[0].end == start.addingTimeInterval(7200))
    }

    @Test("暇登録だけでは参加意思にならない")
    func registeredAvailabilityIsNotParticipation() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let slot = AvailabilitySlot(interval: TimeIntervalRange(start: start, end: start.addingTimeInterval(7200)))
        let hosting = Hosting(
            id: UUID(),
            mode: .online,
            area: nil,
            category: .game,
            candidateRange: slot.interval,
            requiredDuration: 3600,
            friends: [],
            participants: [],
            status: .recruiting
        )

        #expect(hosting.participants.isEmpty)
        #expect(hosting.status == .recruiting)
    }
}
