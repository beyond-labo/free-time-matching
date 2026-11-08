import Foundation
import Testing
@testable import Himatch

private let calendar = AvailabilityTestClock.calendar
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    AvailabilityTestClock.date(day: day, hour: hour, minute: minute)
}
private func range(_ start: Date, _ end: Date) -> TimeIntervalRange { TimeIntervalRange(start: start, end: end) }
private func same(_ a: TimeIntervalRange?, _ b: TimeIntervalRange) -> Bool { a?.start == b.start && a?.end == b.end }

func makeHosting(
    id: UUID = UUID(),
    range: TimeIntervalRange,
    participants: [Participation] = [],
    status: HostingStatus = .recruiting,
    hostedByMe: Bool = true,
    myInvitation: HostingInvitation? = nil,
    friends: [FriendProfile] = []
) -> Hosting {
    Hosting(
        id: id, mode: .online, area: nil, category: nil, candidateRange: range,
        requiredDuration: AvailabilityPolicy.quarterHour, friends: friends, participants: participants,
        status: status, myInvitation: myInvitation, isHostedByMe: hostedByMe
    )
}

func friend(_ name: String, id: UUID = UUID()) -> FriendProfile {
    FriendProfile(id: id, displayName: name, icon: PresetProfileIcon.sun.rawValue)
}

@Suite("時間候補")
struct TimeCandidatePolicyTests {
    // 2026-09-01 is a Tuesday; the nearest Saturday is 09-05.
    private func candidates(now: Date, availability: [AvailabilitySlot] = [], hostings: [TimeIntervalRange] = []) -> [TimeCandidate] {
        TimeCandidatePolicy.candidates(now: now, calendar: calendar, availability: availability, activeHostingRanges: hostings)
    }

    @Test("16:00 は今夜・明日の夜・土曜の午後を返す")
    func afternoonReturnsThreeFixedCandidates() {
        let result = candidates(now: at(1, 16))
        #expect(result.map(\.kind) == [.tonight, .tomorrowNight, .saturdayAfternoon])
        #expect(same(result[0].range, range(at(1, 19), at(1, 22))))
        #expect(same(result[1].range, range(at(2, 19), at(2, 22))))
        #expect(same(result[2].range, range(at(5, 13), at(5, 17))))
    }

    @Test("開始後の今夜は次の15分境界から始まる")
    func startedTonightMovesToNextQuarter() {
        let result = candidates(now: at(1, 19, 30))
        #expect(result.first?.kind == .tonight)
        #expect(result.first?.range.start == at(1, 19, 45))
        #expect(result.first?.range.end == at(1, 22))
    }

    @Test("残り1時間未満の今夜は表示しない")
    func shortTonightIsDropped() {
        let result = candidates(now: at(1, 21, 10))
        #expect(!result.contains { $0.kind == .tonight })
        #expect(result.first?.kind == .tomorrowNight)
    }

    @Test("土曜当日は当日の午後を候補にする")
    func saturdayUsesSameDay() {
        let result = candidates(now: at(5, 10))
        #expect(result.contains { $0.kind == .saturdayAfternoon && same($0.range, range(at(5, 13), at(5, 17))) })
    }

    @Test("14日の範囲外の候補は返さない")
    func outsideWindowIsDropped() {
        let late = AvailabilitySlot(interval: range(at(15, 21), at(15, 23)))
        let result = candidates(now: at(1, 20), availability: [late])
        #expect(!result.contains { if case .availability = $0.kind { true } else { false } })
    }

    @Test("暇候補は募集中と重ならないものを開始順に最大2件")
    func availabilityCandidatesAreFilteredAndCapped() {
        let busy = AvailabilitySlot(interval: range(at(2, 10), at(2, 12)))
        let a = AvailabilitySlot(interval: range(at(3, 10), at(3, 12)))
        let b = AvailabilitySlot(interval: range(at(4, 10), at(4, 12)))
        let c = AvailabilitySlot(interval: range(at(6, 10), at(6, 12)))
        let result = candidates(now: at(1, 16), availability: [c, b, busy, a], hostings: [range(at(2, 11), at(2, 13))])
        let ids = result.compactMap { if case let .availability(id) = $0.kind { id } else { nil } }
        #expect(ids == [a.id, b.id])
    }
}

@Suite("返事の選択肢")
struct ReplyChoicePolicyTests {
    @Test("2時間未満は全部だけ")
    func shortCandidateHasOnlyWhole() {
        let presets = ReplyChoicePolicy.presets(for: range(at(1, 19), at(1, 20, 45)))
        #expect(presets.map(\.choice) == [.whole])
    }

    @Test("3時間は1時間30分で分ける")
    func threeHoursSplitsInHalf() {
        let presets = ReplyChoicePolicy.presets(for: range(at(1, 19), at(1, 22)))
        #expect(presets.map(\.choice) == [.whole, .firstHalf, .secondHalf])
        #expect(same(presets[1].range, range(at(1, 19), at(1, 20, 30))))
        #expect(same(presets[2].range, range(at(1, 20, 30), at(1, 22))))
    }

    @Test("2時間15分の中点は15分境界に丸める")
    func midpointIsQuarterAligned() {
        let mid = ReplyChoicePolicy.midpoint(of: range(at(1, 19), at(1, 21, 15)))
        #expect(mid == at(1, 20, 15) || mid == at(1, 20))
        #expect(AvailabilityPolicy.isQuarterHourAligned(mid, calendar: calendar))
    }

    @Test("指定範囲は候補内の15分境界だけを許可する")
    func customRangeBounds() {
        let candidate = range(at(1, 19), at(1, 21))
        #expect(ReplyChoicePolicy.customStarts(in: candidate).count == 8)
        #expect(ReplyChoicePolicy.customEnds(in: candidate, after: at(1, 20, 30)) == [at(1, 20, 45), at(1, 21)])
        #expect(ReplyChoicePolicy.isValidCustom(range(at(1, 19, 15), at(1, 20)), in: candidate))
        #expect(!ReplyChoicePolicy.isValidCustom(range(at(1, 18, 45), at(1, 20)), in: candidate))
        #expect(!ReplyChoicePolicy.isValidCustom(range(at(1, 19, 10), at(1, 20)), in: candidate))
    }
}

@Suite("参加OKの新着と全員そろう時間")
struct ParticipationNoticeTests {
    let hostingID = UUID()
    let participationID = UUID()

    private func hosting(_ intervals: [TimeIntervalRange], status: HostingStatus = .recruiting, hostedByMe: Bool = true) -> Hosting {
        makeHosting(
            id: hostingID, range: range(at(1, 19), at(1, 22)),
            participants: [Participation(id: participationID, friend: friend("田中"), approvedIntervals: intervals)],
            status: status, hostedByMe: hostedByMe
        )
    }

    @Test("未読の参加OKを新着として返す")
    func unseenIsNew() {
        let notices = ParticipationNoticeDetector.newNotices(hostings: [hosting([range(at(1, 19), at(1, 20))])], seenKeys: [])
        #expect(notices.count == 1)
        #expect(notices.first?.isChange == false)
    }

    @Test("既読は返さず、時間変更は変更として返す")
    func seenAndChanged() {
        let original = hosting([range(at(1, 19), at(1, 20))])
        let seen = ParticipationNoticeDetector.activeKeys(hostings: [original])
        #expect(ParticipationNoticeDetector.newNotices(hostings: [original], seenKeys: seen).isEmpty)
        let changed = hosting([range(at(1, 19), at(1, 21))])
        let notices = ParticipationNoticeDetector.newNotices(hostings: [changed], seenKeys: seen)
        #expect(notices.first?.isChange == true)
    }

    @Test("取消済みと他人の募集は対象外")
    func excludesClosedAndOthers() {
        #expect(ParticipationNoticeDetector.newNotices(hostings: [hosting([range(at(1, 19), at(1, 20))], status: .cancelled)], seenKeys: []).isEmpty)
        #expect(ParticipationNoticeDetector.newNotices(hostings: [hosting([range(at(1, 19), at(1, 20))], hostedByMe: false)], seenKeys: []).isEmpty)
    }

    @Test("既読キーに名前を含めない")
    func keyHasNoName() {
        let key = ParticipationNoticeDetector.key(hostingID: hostingID, participationID: participationID, intervals: [range(at(1, 19), at(1, 20))])
        #expect(!key.contains("田中"))
    }

    @Test("全員そろう時間は2人以上の重なり")
    func everyoneAvailable() {
        let candidate = range(at(1, 19), at(1, 22))
        let a = Participation(id: UUID(), friend: friend("田中"), approvedIntervals: [range(at(1, 19), at(1, 20, 30))])
        let b = Participation(id: UUID(), friend: friend("佐藤"), approvedIntervals: [range(at(1, 19, 30), at(1, 21))])
        let c = Participation(id: UUID(), friend: friend("鈴木"), approvedIntervals: [range(at(1, 21), at(1, 22))])
        #expect(HostingPolicy.everyoneAvailable(candidate: candidate, participants: [a]) == nil)
        let both = HostingPolicy.everyoneAvailable(candidate: candidate, participants: [a, b])
        #expect(both?.start == at(1, 19, 30))
        #expect(both?.end == at(1, 20, 30))
        #expect(HostingPolicy.everyoneAvailable(candidate: candidate, participants: [a, c]) == nil)
    }
}

@Suite("はじめての予定の段階")
struct FirstMatchProgressTests {
    private let now = at(1, 16)

    private func snapshot(friends: Int = 0, availability: Bool = false, hostings: [Hosting] = [], invitations: [Hosting] = []) -> AppSnapshot {
        var value = AppSnapshot.empty()
        value.friends = (0..<friends).map { friend("友達\($0)") }
        if availability {
            let id = UUID()
            value.availability = [AvailabilitySlot(id: id, interval: TimeIntervalRange(id: id, start: at(2, 19), end: at(2, 22)), category: nil, visibility: .privateUntilAccepted)]
        }
        value.hostings = hostings
        value.invitations = invitations
        return value
    }

    private func scheduling(enabled: Bool, permit friends: [FriendProfile] = [], proposals: [SchedulingProposal] = []) -> SchedulingSnapshot {
        SchedulingSnapshot(enabled: enabled, permissions: friends.map { SchedulingPermission(friendId: $0.id, enabled: true) },
                           proposals: proposals, notifications: [])
    }

    private func proposal(_ status: SchedulingProposal.Status, my: SchedulingProposal.Response = .pending) -> SchedulingProposal {
        SchedulingProposal(id: UUID(), start: at(2, 19), end: at(2, 21), status: status, myResponse: my, version: 1,
                           shareAcceptance: false, peer: nil, peerResponse: nil, feedback: nil)
    }

    private func evaluate(_ snapshot: AppSnapshot, _ scheduling: SchedulingSnapshot? = nil, record: FirstMatchRecord = FirstMatchRecord()) -> FirstMatchStep? {
        FirstMatchProgress.evaluate(snapshot: snapshot, scheduling: scheduling, record: record, now: now)
    }

    @Test("友達0人はつながる段階で、共有済みかを保持する")
    func connectStep() {
        #expect(evaluate(snapshot()) == .connectFriends(codeShared: false))
        var record = FirstMatchRecord()
        record.inviteCodeShared = true
        #expect(evaluate(snapshot(), record: record) == .connectFriends(codeShared: true))
    }

    @Test("友達がいれば暇・自動提案・友達別許可の準備を順に確認する")
    func preparation() {
        let value = snapshot(friends: 1)
        #expect(evaluate(value) == .prepareProposals(FirstMatchReadiness(hasAvailability: false, proposalsEnabled: false, hasPermittedFriend: false)))
        let withSlot = snapshot(friends: 1, availability: true)
        #expect(evaluate(withSlot, scheduling(enabled: true)) == .prepareProposals(FirstMatchReadiness(hasAvailability: true, proposalsEnabled: true, hasPermittedFriend: false)))
        #expect(evaluate(withSlot, scheduling(enabled: true, permit: withSlot.friends)) == .answerProposal(hasPendingProposal: false))
    }

    @Test("準備が整うと、届いた提案への参加OKを促す")
    func answerStep() {
        let value = snapshot(friends: 1, availability: true)
        let pending = scheduling(enabled: true, permit: value.friends, proposals: [proposal(.pending)])
        #expect(evaluate(value, pending) == .answerProposal(hasPendingProposal: true))
        let answered = scheduling(enabled: true, permit: value.friends, proposals: [proposal(.pending, my: .accepted)])
        #expect(evaluate(value, answered) == .answerProposal(hasPendingProposal: false))
    }

    @Test("提案で予定が確定するか、手動のお誘いで参加OKをやり取りすると完了")
    func completion() {
        #expect(FirstMatchProgress.isCompleted(snapshot: snapshot(friends: 1), scheduling: scheduling(enabled: true, proposals: [proposal(.confirmed, my: .accepted)])))
        let accepted = makeHosting(
            range: range(at(1, 19), at(1, 22)),
            participants: [Participation(id: UUID(), friend: friend("田中"), approvedIntervals: [range(at(1, 19), at(1, 20))])]
        )
        #expect(FirstMatchProgress.isCompleted(snapshot: snapshot(friends: 1, hostings: [accepted]), scheduling: nil))
        let answered = makeHosting(
            range: range(at(1, 19), at(1, 22)), hostedByMe: false,
            myInvitation: HostingInvitation(status: .accepted, version: 2, intervals: [range(at(1, 19), at(1, 20))])
        )
        #expect(FirstMatchProgress.isCompleted(snapshot: snapshot(friends: 1, invitations: [answered]), scheduling: nil))
        #expect(evaluate(snapshot(friends: 1, invitations: [answered])) == nil)
        #expect(!FirstMatchProgress.isCompleted(snapshot: snapshot(friends: 1), scheduling: scheduling(enabled: true, proposals: [proposal(.declined)])))
    }

    @Test("完了または閉じた案内は表示しない")
    func hiddenAfterRecord() {
        var record = FirstMatchRecord()
        record.guide = .dismissed
        #expect(evaluate(snapshot(), record: record) == nil)
        record.guide = .completed
        #expect(evaluate(snapshot(), record: record) == nil)
    }
}

@Suite("端末内の記録")
struct FirstMatchLocalStoreTests {
    @Test("アカウント別に保存・読込・削除する")
    func perAccount() throws {
        let suite = "FirstMatchLocalStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FirstMatchLocalStore.userDefaults(defaults)
        var record = FirstMatchRecord()
        record.guide = .completed
        record.lastMeeting = LastMeeting(mode: .offline, area: .shibuya)
        store.save("user-a", record)

        #expect(store.load("user-a") == record)
        #expect(store.load("user-b") == FirstMatchRecord())
        store.remove("user-a")
        #expect(store.load("user-a") == FirstMatchRecord())
    }

    @Test("壊れた値は既定値として読む")
    func corruptValueFallsBack() throws {
        let suite = "FirstMatchLocalStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: "firstMatch.user-a")
        #expect(FirstMatchLocalStore.userDefaults(defaults).load("user-a") == FirstMatchRecord())
    }
}
