import Foundation
import Testing
@testable import Himatch

struct SystemActionEntityTests {
    @Test func onlineConditionsDoNotMentionAnOfflineArea() {
        let input = SystemActionInput(kind: .createHosting, mode: .online, area: .shinjuku)
        let prepared = PreparedSystemAction(operationID: UUID(), ownerUserID: "owner", input: input,
                                            expectedVersion: nil, confirmationFingerprint: "test")
        let text = SystemActionIntentText.confirmation(prepared, friends: [])
        #expect(text.contains("オンライン"))
        #expect(!text.contains("あとで相談"))
        #expect(!text.contains("新宿"))
        #expect(SystemActionIntentText.conditions(mode: .online, category: nil, area: nil) == "オンライン、カテゴリ指定なし")
        #expect(SystemActionIntentText.conditions(mode: .offline, category: nil, area: nil).contains("あとで相談"))
    }

    @Test func invalidDatesSelectOnlyTheParameterThatNeedsCorrection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = AvailabilityPolicy.nextQuarterHour(after: now)
        let end = start.addingTimeInterval(3600)
        var input = SystemActionInput(kind: .addAvailability, start: start, end: end)
        #expect(SystemActionDateIssue.validate(input, now: now) == nil)
        input.start = now.addingTimeInterval(-900)
        guard case .start? = SystemActionDateIssue.validate(input, now: now) else {
            Issue.record("Past start must request only start")
            return
        }
        input.start = start
        input.end = start
        guard case .end? = SystemActionDateIssue.validate(input, now: now) else {
            Issue.record("End at start must request only end")
            return
        }
        input.end = end.addingTimeInterval(60)
        #expect(SystemActionDateIssue.validate(input, now: now) == .end("終了日時は15分単位を指定してください。"))
        input.end = now.addingTimeInterval(AvailabilityPolicy.window + 900)
        #expect(SystemActionDateIssue.validate(input, now: now) == .end("終了日時は14日以内を指定してください。"))
    }

    @Test func fixedAppEnumsCoverDomainChoices() {
        #expect(Set(SystemHostingMode.allCases.map { $0.domainValue.rawValue }) == Set(HostingMode.allCases.map(\.rawValue)))
        #expect(Set(SystemHostingArea.allCases.map { $0.domainValue.rawValue }) == Set(HostingArea.allCases.map(\.rawValue)))
        #expect(Set(SystemActivityCategory.allCases.map { $0.domainValue.rawValue }) == Set(ActivityCategory.allCases.map(\.rawValue)))
    }
    @Test func sameNameFriendsResolveByOwnerAndUUID() {
        let first = FriendEntity(ownerUserID: "owner", userID: UUID(), nickname: "ゆう", presetIconKey: "star")
        let second = FriendEntity(ownerUserID: "owner", userID: UUID(), nickname: "ゆう", presetIconKey: "moon")
        let selected = FriendEntityQuery.resolve([second.id], candidates: [first, second])
        #expect(selected.map(\.userID) == [second.userID])
        let foreignID = SystemActionEntityID.make(owner: "other", target: second.userID)
        #expect(FriendEntityQuery.resolve([foreignID], candidates: [first, second]).isEmpty)
        #expect(FriendEntityQuery.resolve([second.id], candidates: []).isEmpty)
    }

    @Test func hostingCandidatesExcludeInvitationsAndInactiveHostings() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let mine = Hosting(id: UUID(), mode: .online, candidateRange: .init(start: start, end: start.addingTimeInterval(3600)),
                           requiredDuration: 900, friends: [], participants: [], status: .recruiting)
        var invite = mine
        invite.isHostedByMe = false
        var cancelled = mine
        cancelled.status = .cancelled
        let candidates = OwnedHostingEntityQuery.candidates(ownerUserID: "owner", hostings: [mine, invite, cancelled])
        #expect(candidates.map(\.hostingID) == [mine.id])
        #expect(candidates.first?.ownerUserID == "owner")
    }

    @Test func compositeIDRetainsAccountAndRejectsMalformedValues() {
        let target = UUID()
        let parsed = SystemActionEntityID.parse(SystemActionEntityID.make(owner: "account", target: target))
        #expect(parsed?.owner == "account")
        #expect(parsed?.target == target)
        #expect(SystemActionEntityID.parse(target.uuidString) == nil)
        #expect(SystemActionEntityID.parse(":\(target.uuidString)") == nil)
    }

    @Test func confirmationIncludesCrossDayDatesAndSelectedFriends() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let input = SystemActionInput(kind: .createHosting, start: start, end: start.addingTimeInterval(86400),
                                     timeZoneIdentifier: "Asia/Tokyo", mode: .offline, area: .discussLater)
        let prepared = PreparedSystemAction(operationID: UUID(), ownerUserID: "owner", input: input,
                                            expectedVersion: nil, confirmationFingerprint: "test")
        let friend = FriendEntity(ownerUserID: "owner", userID: UUID(), nickname: "ゆう", presetIconKey: "star")
        let text = SystemActionIntentText.confirmation(prepared, friends: [friend])
        #expect(text.contains("あとで相談"))
        #expect(text.contains("ゆう"))
        #expect(text.contains("オフライン"))
        #expect(text.contains("から"))
        #expect(text.contains("年"))
        #expect(text.contains("Asia/Tokyo"))
        #expect(text.contains("全員に招待"))
    }
}
