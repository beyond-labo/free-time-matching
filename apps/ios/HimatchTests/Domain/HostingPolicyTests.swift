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

    @Test("回答期限は募集候補の開始時刻")
    func answerDeadlineUsesCandidateStart() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let hosting = Hosting(
            id: UUID(),
            mode: .online,
            area: nil,
            category: nil,
            candidateRange: TimeIntervalRange(start: start, end: start.addingTimeInterval(3600)),
            requiredDuration: 0,
            friends: [],
            participants: [],
            status: .recruiting
        )

        #expect(hosting.answerDeadline == start)
    }

    @Test("招待回答は候補全体を初期選択せず、15分枠の明示確認を求める")
    func invitationResponseRequiresExplicitRangeChoice() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let candidate = TimeIntervalRange(start: start, end: start.addingTimeInterval(3600))
        var selection = InvitationResponseSelection(candidateRange: candidate)

        #expect(selection.range.duration == 900)
        #expect(!selection.isConfirmed)
        selection.stepEnd(by: 2)
        #expect(selection.range.end == start.addingTimeInterval(2700))
        #expect(!selection.isConfirmed)
        selection.confirm()
        #expect(selection.isConfirmed)
        selection.stepStart(by: 1)
        #expect(!selection.isConfirmed)
        #expect(selection.range.start >= candidate.start)
        #expect(selection.range.end <= candidate.end)
    }
}
