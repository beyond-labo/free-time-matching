import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("はじめてのお誘い：デモ")
struct FirstMatchDemoTests {
    private let now = AvailabilityTestClock.date(day: 1, hour: 16, minute: 0)

    private func makeStore(seed: HimatchPrototypeScenario.Seed = .noFriends) -> TestStoreOf<AppFeature> {
        let scenario = HimatchPrototypeScenario(now: now, seed: seed)
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
            $0.demoScenarioClient = .live(scenario)
            $0.firstMatchLocalStore = .inMemory()
            $0.date.now = now
            $0.calendar = AvailabilityTestClock.calendar
        }
        store.exhaustivity = .off
        return store
    }

    @Test("デモではプロフィール保存が成功してホームへ進む")
    func demoProfileSaveReachesHome() async {
        let store = makeStore()
        await store.send(.startDemo(.noFriends)) {
            $0.isDemo = true
            $0.route = .profile
        }
        await store.receive(\.demoSnapshotLoaded) {
            $0.profileName = "ひまり"
            $0.isLoading = false
        }
        await store.send(.saveProfileTapped)
        await store.receive(\.profileSaved) {
            $0.route = .main
            $0.snapshot?.profileName = "ひまり"
        }
        #expect(store.state.alertMessage == nil)
        #expect(store.state.snapshot?.friends.isEmpty == true)
    }

    @Test("友達ありで始めると友達と未回答のお誘いがある")
    func withFriendsSeed() async {
        let store = makeStore()
        await store.send(.startDemo(.withFriends))
        await store.receive(\.demoSnapshotLoaded)
        #expect(store.state.snapshot?.friends.count == 3)
        #expect(store.state.snapshot?.invitations.first?.myInvitation?.status == .pending)
        #expect(store.state.snapshot?.invitations.first?.isHostedByMe == false)
    }

    @Test("デモ友達の申請を承認すると友達がつながる")
    func demoFriendRequestConnects() async {
        let store = makeStore()
        await store.send(.startDemo(.noFriends))
        await store.receive(\.demoSnapshotLoaded)
        await store.send(.demoFriendRequestTapped)
        await store.receive(\.snapshotMutationCompleted)
        let requestID = try! #require(store.state.snapshot?.requests.first?.id)
        await store.send(.acceptRequest(requestID))
        await store.receive(\.snapshotMutationCompleted)
        #expect(store.state.snapshot?.friends.count == 3)
        #expect(store.state.snapshot?.requests.isEmpty == true)
    }
}

private let clock = AvailabilityTestClock.self
private func t(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { clock.date(day: day, hour: hour, minute: minute) }

@MainActor
@Suite("お誘い作成")
struct InvitationComposerFeatureTests {
    let now = t(1, 16)
    let tanaka = friend("田中")
    let sato = friend("佐藤")

    private func candidates(_ availability: [AvailabilitySlot] = []) -> [TimeCandidate] {
        TimeCandidatePolicy.candidates(now: now, calendar: clock.calendar, availability: availability, activeHostingRanges: [])
    }

    private func state(_ start: InvitationStart, availability: [AvailabilitySlot] = [], lastMeeting: LastMeeting? = nil) -> InvitationComposerFeature.State {
        InvitationComposerFeature.State(
            start: start, friends: [tanaka, sato], availability: availability,
            candidates: candidates(availability), lastMeeting: lastMeeting, now: now, operationID: UUID(0)
        )
    }

    private func store(_ initial: InvitationComposerFeature.State) -> TestStoreOf<InvitationComposerFeature> {
        TestStore(initialState: initial) { InvitationComposerFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.calendar = clock.calendar
        }
    }

    @Test("候補から開くと時間が選択済みで、初回の会い方は未選択")
    func candidateStart() {
        let tonight = candidates()[0]
        let value = state(.candidate(tonight))
        #expect(value.range?.start == t(1, 19))
        #expect(value.selectedCandidateID == tonight.id)
        #expect(value.mode == nil)
        #expect(value.missingItem == .friends)
    }

    @Test("友達から開くとその友達が選択済み、前回の会い方を初期値にする")
    func friendStartWithLastMeeting() {
        let value = state(.friend(sato.id), lastMeeting: LastMeeting(mode: .offline, area: .shibuya))
        #expect(value.selectedFriendIDs == [sato.id])
        #expect(value.mode == .offline)
        #expect(value.area == .shibuya)
        #expect(value.missingItem == .time)
    }

    @Test("不足項目は時間・友達・会い方・エリアの順で解消される")
    func missingItemsInOrder() async {
        let store = store(state(.blank))
        #expect(store.state.missingItem == .time)
        await store.send(.candidateSelected("tonight")) {
            $0.selectedCandidateID = "tonight"
            $0.range = QuarterRange(start: t(1, 19), end: t(1, 22))
            $0.operationID = UUID(0)
        }
        #expect(store.state.missingItem == .friends)
        await store.send(.friendToggled(tanaka.id)) {
            $0.selectedFriendIDs = [tanaka.id]
            $0.operationID = UUID(1)
        }
        #expect(store.state.missingItem == .mode)
        await store.send(.modeSelected(.offline)) {
            $0.mode = .offline
            $0.operationID = UUID(2)
        }
        #expect(store.state.missingItem == .area)
        await store.send(.areaSelected(.shibuya)) {
            $0.area = .shibuya
            $0.operationID = UUID(3)
        }
        #expect(store.state.missingItem == nil)
    }

    @Test("送信すると新規範囲を未選択・非公開の暇として下書きを返す")
    func submitBuildsPrivateDraft() async {
        var initial = state(.candidate(candidates()[0]))
        initial.selectedFriendIDs = [tanaka.id]
        initial.mode = .online
        let store = store(initial)
        await store.send(.submitTapped) { $0.isSubmitting = true }
        await store.receive(\.delegate.submit)
        let expected = HostingAvailabilityMetadata(category: nil, visibility: .privateUntilAccepted)
        #expect(store.state.availabilityMetadata == expected)
        await store.send(.submissionFailed("通信に失敗しました")) {
            $0.isSubmitting = false
            $0.errorMessage = "通信に失敗しました"
        }
        #expect(store.state.range?.start == t(1, 19))
    }

    @Test("属性の異なる既存暇と重なると、選ぶまで送信できない")
    func conflictBlocksSubmit() async {
        let shared = AvailabilitySlot(interval: TimeIntervalRange(start: t(1, 21), end: t(1, 23)), category: .game, visibility: .shareOnHosting)
        var initial = state(.candidate(candidates([shared])[0]), availability: [shared])
        initial.selectedFriendIDs = [tanaka.id]
        initial.mode = .online
        #expect(initial.missingItem == .availabilityMetadata)
        let store = store(initial)
        await store.send(.submitTapped)
        await store.send(.availabilityMetadataChosen(nil, .privateUntilAccepted)) {
            $0.availabilityConflict?.chosen = HostingAvailabilityMetadata(category: nil, visibility: .privateUntilAccepted)
            $0.operationID = UUID(0)
        }
        #expect(store.state.missingItem == nil)
    }

    @Test("既存暇の内側から誘うときはその暇の設定を引き継ぐ")
    func insideExistingSlotKeepsAttributes() {
        let slot = AvailabilitySlot(interval: TimeIntervalRange(start: t(2, 10), end: t(2, 14)), category: .meal, visibility: .shareOnHosting)
        let value = state(.range(QuarterRange(start: t(2, 11), end: t(2, 13))), availability: [slot])
        #expect(value.availabilityConflict == nil)
        #expect(value.availabilityMetadata == HostingAvailabilityMetadata(category: .meal, visibility: .shareOnHosting))
        #expect(value.isCustomTime)
    }
}

@MainActor
@Suite("返事")
struct InvitationReplyFeatureTests {
    let now = t(1, 16)

    private func invitation(status: HostingStatus = .recruiting, mine: HostingInvitation? = HostingInvitation(status: .pending, version: 1, intervals: nil)) -> Hosting {
        makeHosting(range: TimeIntervalRange(start: t(1, 19), end: t(1, 22)), status: status, hostedByMe: false, myInvitation: mine)
    }

    @Test("初期状態では何も選択せず送信できない")
    func nothingPreselected() {
        let state = InvitationReplyFeature.State(invitation: invitation(), now: now)
        #expect(state.choice == nil)
        #expect(!state.canAccept)
        #expect(state.presets.map(\.choice) == [.whole, .firstHalf, .secondHalf])
    }

    @Test("選択肢を選ぶと1回の操作で参加OKを返す")
    func acceptInOneTap() async {
        let store = TestStore(initialState: InvitationReplyFeature.State(invitation: invitation(), now: now)) { InvitationReplyFeature() }
        await store.send(.choiceSelected(.firstHalf)) { $0.choice = .firstHalf }
        await store.send(.acceptTapped) { $0.isSubmitting = true }
        await store.receive(\.delegate.respond)
        await store.send(.submissionFailed("失敗")) {
            $0.isSubmitting = false
            $0.errorMessage = "失敗"
        }
        #expect(store.state.choice == .firstHalf)
        #expect(store.state.selectedRange?.end == t(1, 20, 30))
    }

    @Test("参加OK済みは現在の時間を復元し、取消は辞退として送る")
    func acceptedRestoresAndWithdraws() async {
        let accepted = invitation(mine: HostingInvitation(status: .accepted, version: 2, intervals: [TimeIntervalRange(start: t(1, 19, 30), end: t(1, 20, 15))]))
        let initial = InvitationReplyFeature.State(invitation: accepted, now: now)
        #expect(initial.choice == .custom)
        #expect(initial.selectedRange?.start == t(1, 19, 30))
        let store = TestStore(initialState: initial) { InvitationReplyFeature() }
        await store.send(.withdrawTapped) { $0.isSubmitting = true }
        await store.receive(.delegate(.respond(.declined, [])))
    }

    @Test("取消済みや期限後は返事できない")
    func closedCannotRespond() async {
        var state = InvitationReplyFeature.State(invitation: invitation(status: .cancelled), now: now)
        state.choice = .whole
        #expect(!state.canAccept)
        let late = InvitationReplyFeature.State(invitation: invitation(), now: t(1, 19, 5))
        #expect(!late.canRespond)
        let store = TestStore(initialState: state) { InvitationReplyFeature() }
        await store.send(.acceptTapped)
        await store.send(.declineTapped)
    }
}

@Suite("ホーム投影")
struct HomeDashboardTests {
    let now = t(1, 16)

    private func make(_ snapshot: AppSnapshot, scheduling: SchedulingSnapshot? = nil, record: FirstMatchRecord = FirstMatchRecord()) -> HomeDashboard {
        HomeDashboard.make(snapshot: snapshot, scheduling: scheduling, record: record, now: now, calendar: clock.calendar)
    }

    private func snapshot(friends: Int) -> AppSnapshot {
        var value = AppSnapshot.empty()
        value.friends = (0..<friends).map { friend("友達\($0)") }
        return value
    }

    private func proposal(_ status: SchedulingProposal.Status, my: SchedulingProposal.Response = .pending) -> SchedulingProposal {
        SchedulingProposal(id: UUID(), start: t(2, 19), end: t(2, 21), status: status, myResponse: my, version: 1,
                           shareAcceptance: false, peer: nil, peerResponse: nil, feedback: nil)
    }

    @Test("友達0人でも案内と暇の登録があり、主操作は友達の招待")
    func noFriends() {
        let home = make(snapshot(friends: 0))
        #expect(home.sections.map(\.kind) == ["guide", "availability"])
        #expect(home.primaryAction == .inviteFriendCode)
        #expect(home.noticeCount == 0)
    }

    @Test("友達がいると準備の案内を出し、主操作は暇の登録、自分で誘う候補は副経路")
    func friendsGuidePreparation() {
        let home = make(snapshot(friends: 2), scheduling: .empty)
        #expect(home.sections.map(\.kind) == ["guide", "availability", "timeCandidates"])
        if case let .guide(step, count) = home.sections[0] {
            #expect(step == .prepareProposals(FirstMatchReadiness(hasAvailability: false, proposalsEnabled: false, hasPermittedFriend: false)))
            #expect(count == 2)
        } else { Issue.record("guide missing") }
        #expect(home.primaryAction == .registerAvailability)
    }

    @Test("区分は申請・提案・届いたお誘い・案内・決まった予定・自分のお誘い・暇・自分で誘うの順")
    func sectionOrder() {
        var value = snapshot(friends: 1)
        value.requests = [FriendRequest(id: UUID(), person: friend("ゆい"), direction: .incoming)]
        value.invitations = [makeHosting(range: TimeIntervalRange(start: t(2, 19), end: t(2, 22)), hostedByMe: false,
                                         myInvitation: HostingInvitation(status: .pending, version: 1, intervals: nil))]
        value.hostings = [makeHosting(range: TimeIntervalRange(start: t(1, 19), end: t(1, 22)))]
        let scheduling = SchedulingSnapshot(enabled: true, permissions: [], proposals: [proposal(.pending)], notifications: [])
        var record = FirstMatchRecord()
        record.guide = .active
        let home = make(value, scheduling: scheduling, record: record)
        #expect(home.sections.map(\.kind) == ["friendRequests", "proposals", "invitationsToAnswer", "guide", "myInvitations", "availability", "timeCandidates"])
        #expect(home.noticeCount == 3)

        let confirmed = SchedulingSnapshot(enabled: true, permissions: [], proposals: [proposal(.confirmed, my: .accepted)], notifications: [])
        let afterPlan = make(snapshot(friends: 1), scheduling: confirmed)
        #expect(afterPlan.sections.map(\.kind) == ["confirmedPlans", "availability", "timeCandidates"])
    }

    @Test("案内を閉じた後に自動提案がオフなら提案区分でオフを知らせる")
    func proposalsOffBanner() {
        var record = FirstMatchRecord()
        record.guide = .dismissed
        let home = make(snapshot(friends: 1), scheduling: .empty, record: record)
        #expect(home.sections.first == .proposals([], proposalsOff: true))
    }

    @Test("案内終了後は案内を出さず、未読の参加OKを件数に数える")
    func afterGuide() {
        var value = snapshot(friends: 1)
        value.hostings = [makeHosting(
            range: TimeIntervalRange(start: t(1, 19), end: t(1, 22)),
            participants: [Participation(id: UUID(), friend: friend("田中"), approvedIntervals: [TimeIntervalRange(start: t(1, 19), end: t(1, 20))])]
        )]
        let home = make(value)
        #expect(!home.sections.map(\.kind).contains("guide"))
        #expect(home.noticeCount == 1)
        var record = FirstMatchRecord()
        record.seenParticipationKeys = ParticipationNoticeDetector.activeKeys(hostings: value.hostings)
        #expect(make(value, record: record).noticeCount == 0)
    }

    @Test("回答済みのお誘いと提案は件数に数えない")
    func answeredNotCounted() {
        var value = snapshot(friends: 1)
        value.invitations = [makeHosting(range: TimeIntervalRange(start: t(2, 19), end: t(2, 22)), hostedByMe: false,
                                         myInvitation: HostingInvitation(status: .accepted, version: 2, intervals: [TimeIntervalRange(start: t(2, 19), end: t(2, 20))]))]
        #expect(make(value).noticeCount == 0)
        #expect(make(value).sections.map(\.kind).contains("invitationsToAnswer"))
        let answered = SchedulingSnapshot(enabled: true, permissions: [], proposals: [proposal(.pending, my: .accepted)], notifications: [])
        #expect(make(snapshot(friends: 1), scheduling: answered).noticeCount == 0)
    }
}

@MainActor
@Suite("参加OKの受け取りと案内の記録")
struct FirstMatchRootTests {
    let now = t(1, 16)
    let tanaka = friend("田中")

    private func hosting(participants: [Participation] = []) -> Hosting {
        makeHosting(id: UUID(90), range: TimeIntervalRange(start: t(1, 19), end: t(1, 22)), participants: participants, friends: [tanaka])
    }

    private func store(_ snapshot: AppSnapshot, records: FirstMatchLocalStore, client: HimatchClient = .productionPlaceholder) -> TestStoreOf<AppFeature> {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "user-1", accessToken: "access")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
            $0.firstMatchLocalStore = records
            $0.date.now = now
            $0.calendar = clock.calendar
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        return store
    }

    @Test("新しい参加OKでバナーと件数を出し、お知らせを開くと既読にする")
    func participationBannerAndSeen() async {
        var snapshot = AppSnapshot.empty()
        snapshot.friends = [tanaka]
        snapshot.hostings = [hosting()]
        let records = FirstMatchLocalStore.inMemory()
        let accepted = hosting(participants: [Participation(id: UUID(91), friend: tanaka, approvedIntervals: [TimeIntervalRange(start: t(1, 19), end: t(1, 20, 30))])])
        var client = HimatchClient.productionPlaceholder
        client.loadHostings = { ([accepted], []) }
        let store = store(snapshot, records: records, client: client)

        await store.send(.hostingLoadCompleted([accepted], [], revision: 0, userID: "user-1"))
        #expect(store.state.participationBanner?.title == "田中さんが参加OK")
        #expect(HomeDashboard.make(snapshot: store.state.snapshot!, record: store.state.firstMatchRecord, now: now, calendar: clock.calendar).noticeCount == 1)
        #expect(records.load("user-1").guide == .completed)

        await store.send(.participationBannerDismissed)
        await store.send(.homeAppeared)
        await store.receive(\.hostingLoadCompleted)
        #expect(store.state.participationBanner == nil)

        await store.send(.showInbox(true))
        await store.receive(\.hostingLoadCompleted)
        #expect(!records.load("user-1").seenParticipationKeys.isEmpty)
        #expect(HomeDashboard.make(snapshot: store.state.snapshot!, record: store.state.firstMatchRecord, now: now, calendar: clock.calendar).noticeCount == 0)
    }

    @Test("時間の変更は改めて通知する")
    func changedTimeNotifiesAgain() async {
        let first = hosting(participants: [Participation(id: UUID(91), friend: tanaka, approvedIntervals: [TimeIntervalRange(start: t(1, 19), end: t(1, 20))])])
        var snapshot = AppSnapshot.empty()
        snapshot.friends = [tanaka]
        snapshot.hostings = [first]
        let records = FirstMatchLocalStore.inMemory()
        var record = FirstMatchRecord()
        record.seenParticipationKeys = ParticipationNoticeDetector.activeKeys(hostings: [first])
        records.save("user-1", record)
        let store = store(snapshot, records: records)
        let changed = hosting(participants: [Participation(id: UUID(91), friend: tanaka, approvedIntervals: [TimeIntervalRange(start: t(1, 19), end: t(1, 21))])])
        await store.send(.hostingLoadCompleted([changed], [], revision: 0, userID: "user-1"))
        #expect(store.state.participationBanner?.title == "田中さんが時間を変えました")
    }

    @Test("案内を閉じる・コード共有を記録し、アカウント削除で記録を消す")
    func guideRecordLifecycle() async {
        var snapshot = AppSnapshot.empty()
        snapshot.inviteCode = InviteCode(value: "HIMA-TEST", expiresAt: t(8, 0))
        let records = FirstMatchLocalStore.inMemory()
        let store = store(snapshot, records: records)
        await store.send(.inviteCodeShared)
        #expect(records.load("user-1").inviteCodeShared)
        #expect(FirstMatchProgress.evaluate(snapshot: store.state.snapshot!, scheduling: nil, record: store.state.firstMatchRecord, now: now) == .connectFriends(codeShared: true))
        await store.send(.dismissGuide)
        #expect(records.load("user-1").guide == .dismissed)
        await store.send(.deletionSubmitted(AccountDeletionReceipt(reference: "DEL-1", status: .accepted, statusToken: "token", message: nil)))
        #expect(records.load("user-1") == FirstMatchRecord())
    }

    @Test("返事の delegate は既存の回答操作に変換し、成功で画面を閉じる")
    func replyDelegateUsesExistingResponse() async {
        let pending = makeHosting(
            id: UUID(95), range: TimeIntervalRange(start: t(2, 19), end: t(2, 22)), hostedByMe: false,
            myInvitation: HostingInvitation(status: .pending, version: 3, intervals: nil)
        )
        var accepted = pending
        accepted.myInvitation = HostingInvitation(status: .accepted, version: 4, intervals: [TimeIntervalRange(start: t(2, 19), end: t(2, 22))])
        var response = AppSnapshot.empty()
        response.invitations = [accepted]
        let responseSnapshot = response
        let captured = LockIsolated<(HostingInvitation.Status, Int)?>(nil)
        var client = HimatchClient.productionPlaceholder
        client.respondInvitation = { _, status, _, _, version in
            captured.setValue((status, version))
            return responseSnapshot
        }
        var snapshot = AppSnapshot.empty()
        snapshot.friends = [tanaka]
        snapshot.invitations = [pending]
        let store = store(snapshot, records: .inMemory(), client: client)
        await store.send(.openReply(pending.id))
        #expect(store.state.reply?.choice == nil)
        await store.send(.reply(.presented(.choiceSelected(.whole))))
        await store.send(.reply(.presented(.acceptTapped)))
        await store.receive(\.reply.presented.delegate.respond)
        await store.receive(\.respondToInvitation)
        await store.receive(\.hostingMutationCompleted)
        #expect(captured.value?.0 == .accepted)
        #expect(captured.value?.1 == 3)
        #expect(store.state.reply == nil)
        #expect(store.state.inboxPresented == false)
    }

    @Test("返事の送信失敗は返事画面に残して選択を保持する")
    func replyFailureStaysOnSheet() async {
        let pending = makeHosting(
            id: UUID(96), range: TimeIntervalRange(start: t(2, 19), end: t(2, 22)), hostedByMe: false,
            myInvitation: HostingInvitation(status: .pending, version: 1, intervals: nil)
        )
        var client = HimatchClient.productionPlaceholder
        client.respondInvitation = { _, _, _, _, _ in throw BackendClientError.response(503, "混雑") }
        var snapshot = AppSnapshot.empty()
        snapshot.invitations = [pending]
        let store = store(snapshot, records: .inMemory(), client: client)
        await store.send(.openReply(pending.id))
        await store.send(.reply(.presented(.choiceSelected(.secondHalf))))
        await store.send(.reply(.presented(.acceptTapped)))
        await store.receive(\.responseFailed)
        await store.receive(\.reply.presented.submissionFailed)
        #expect(store.state.reply?.choice == .secondHalf)
        #expect(store.state.reply?.errorMessage?.contains("混雑") == true)
        #expect(store.state.alertMessage == nil)
    }
}

@MainActor
@Suite("デモの主要経路")
struct FirstMatchDemoPathTests {
    let now = t(1, 16)

    private func store(seed: HimatchPrototypeScenario.Seed) -> TestStoreOf<AppFeature> {
        let scenario = HimatchPrototypeScenario(now: now, seed: seed)
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
            $0.demoScenarioClient = .live(scenario)
            $0.firstMatchLocalStore = .inMemory()
            $0.date.now = now
            $0.calendar = clock.calendar
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        return store
    }

    @Test("友達なしから参加OKの受け取りまで進める")
    func noFriendsToFirstAcceptance() async {
        let store = store(seed: .noFriends)
        await store.send(.startDemo(.noFriends))
        await store.receive(\.demoSnapshotLoaded)
        await store.send(.saveProfileTapped)
        await store.receive(\.profileSaved)
        #expect(store.state.route == .main)

        await store.send(.primaryActionTapped)
        await store.receive(\.showAddFriend)
        #expect(store.state.addFriendPresented)
        await store.send(.inviteCodeShared)
        await store.send(.showAddFriend(false))
        await store.send(.demoFriendRequestTapped)
        await store.receive(\.snapshotMutationCompleted)
        let request = store.state.snapshot!.requests[0]
        await store.send(.acceptRequest(request.id))
        await store.receive(\.snapshotMutationCompleted)
        #expect(store.state.snapshot?.friends.count == 3)

        let candidates = TimeCandidatePolicy.candidates(
            now: now, calendar: clock.calendar, availability: store.state.snapshot!.availability, activeHostingRanges: []
        )
        await store.send(.startInvitation(.candidate(candidates[0])))
        await store.send(.composer(.presented(.allFriendsToggled)))
        await store.send(.composer(.presented(.modeSelected(.online))))
        await store.send(.composer(.presented(.submitTapped)))
        await store.receive(\.composer.presented.delegate.submit)
        await store.receive(\.hostingCreated)
        let hostingID = try! #require(store.state.sentInvitation?.id)
        await store.send(.sentInvitationDismissed)

        await store.send(.demoAcceptanceTapped(hostingID))
        await store.receive(\.snapshotMutationCompleted)
        #expect(store.state.participationBanner != nil)
        #expect(store.state.firstMatchRecord.guide == .completed)
        #expect(store.state.snapshot?.hostings.first { $0.id == hostingID }?.participants.count == 1)
    }

    @Test("友達ありから届いたお誘いに返事できる")
    func withFriendsReplies() async {
        let store = store(seed: .withFriends)
        await store.send(.startDemo(.withFriends))
        await store.receive(\.demoSnapshotLoaded)
        await store.send(.saveProfileTapped)
        await store.receive(\.profileSaved)
        // An own open invitation must not hide the reply result (demo returns the whole projection).
        await store.send(.startInvitation(.blank))
        await store.send(.composer(.presented(.candidateSelected("tomorrowNight"))))
        await store.send(.composer(.presented(.allFriendsToggled)))
        await store.send(.composer(.presented(.modeSelected(.online))))
        await store.send(.composer(.presented(.submitTapped)))
        await store.receive(\.composer.presented.delegate.submit)
        await store.receive(\.hostingCreated)
        await store.send(.sentInvitationDismissed)
        let invitation = try! #require(store.state.snapshot?.invitations.first)
        await store.send(.openReply(invitation.id))
        await store.send(.reply(.presented(.choiceSelected(.firstHalf))))
        await store.send(.reply(.presented(.acceptTapped)))
        await store.receive(\.reply.presented.delegate.respond)
        await store.receive(\.respondToInvitation)
        await store.receive(\.hostingMutationCompleted)
        #expect(store.state.snapshot?.invitations.first?.myInvitation?.status == .accepted)
        #expect(store.state.snapshot?.hostings.count == 1)
        #expect(store.state.reply == nil)
        let home = HomeDashboard.make(snapshot: store.state.snapshot!, record: store.state.firstMatchRecord, now: now, calendar: clock.calendar)
        #expect(home.noticeCount == 0)
        #expect(store.state.firstMatchRecord.guide == .completed)
    }
}

@MainActor
@Suite("自動提案を主軸にしたデモ")
struct FirstMatchAutomaticDemoTests {
    let now = t(1, 16)

    @Test("友達ありから暇を登録し自動提案を許可すると、提案に参加OKして予定が決まる")
    func proposalConfirmsPlan() async throws {
        let scenario = HimatchPrototypeScenario(now: now, seed: .withFriends)
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
            $0.demoScenarioClient = .live(scenario)
            $0.automaticSchedulingEffects = .routingDemo(live: .unconfigured, demo: $0.demoScenarioClient.scheduling)
            $0.firstMatchLocalStore = .inMemory()
            $0.date.now = now
            $0.calendar = clock.calendar
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        await store.send(.startDemo(.withFriends))
        await store.receive(\.demoSnapshotLoaded)
        await store.send(.saveProfileTapped)
        await store.receive(\.profileSaved)
        await store.receive(\.automaticScheduling.loaded)
        #expect(!(store.state.snapshot?.availability.isEmpty ?? true))

        let friendID = try #require(store.state.snapshot?.friends.first?.id)
        await store.send(.automaticScheduling(.send(.settings(true))))
        await store.receive(\.automaticScheduling.mutationCompleted)
        await store.send(.automaticScheduling(.send(.permission(friendID, true))))
        await store.receive(\.automaticScheduling.mutationCompleted)
        let readiness = FirstMatchProgress.evaluate(
            snapshot: store.state.snapshot!, scheduling: store.state.automaticScheduling.snapshot,
            record: store.state.firstMatchRecord, now: now
        )
        #expect(readiness == .answerProposal(hasPendingProposal: false))

        await store.send(.demoProposalTapped)
        await store.receive(\.automaticScheduling.loaded)
        let proposal = try #require(store.state.automaticScheduling.snapshot?.proposals.first)
        #expect(proposal.status == .pending)
        let home = HomeDashboard.make(snapshot: store.state.snapshot!, scheduling: store.state.automaticScheduling.snapshot,
                                      record: store.state.firstMatchRecord, now: now, calendar: clock.calendar)
        #expect(home.sections.map(\.kind).first == "proposals")

        await store.send(.automaticScheduling(.send(.response(proposal.id, .accepted, shareAcceptance: false, version: proposal.version))))
        await store.receive(\.automaticScheduling.mutationCompleted)
        await store.send(.demoPeerAcceptanceTapped(proposal.id))
        await store.receive(\.automaticScheduling.loaded)
        #expect(store.state.automaticScheduling.snapshot?.proposals.first?.status == .confirmed)
        #expect(store.state.automaticScheduling.snapshot?.proposals.first?.peer != nil)
        #expect(store.state.firstMatchRecord.guide == .completed)
    }
}

@MainActor
@Suite("アカウント境界と再送")
struct FirstMatchBoundaryTests {
    let now = t(1, 16)
    let tanaka = friend("田中")

    private func signedInState(user: String = "user-1") -> AppFeature.State {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: user, accessToken: "access-\(user)")
        state.snapshot = .empty()
        state.snapshot?.friends = [tanaka]
        return state
    }

    private func makeStore(_ state: AppFeature.State, client: HimatchClient = .productionPlaceholder,
                           configure: (inout DependencyValues) -> Void = { _ in }) -> TestStoreOf<AppFeature> {
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
            $0.firstMatchLocalStore = .inMemory()
            $0.date.now = now
            $0.calendar = clock.calendar
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
            configure(&$0)
        }
        store.exhaustivity = .off
        return store
    }

    @Test("別アカウントへ切り替えると作成・返事・送信結果・バナーを破棄する")
    func ownerChangeClearsInvitationState() async {
        var state = signedInState()
        state.composer = InvitationComposerFeature.State(
            start: .blank, friends: [tanaka], availability: [], candidates: [], lastMeeting: nil, now: now, operationID: UUID(1)
        )
        state.sentInvitation = makeHosting(range: TimeIntervalRange(start: t(1, 19), end: t(1, 22)))
        state.participationBanner = ParticipationBanner(title: "田中さんが参加OK", detail: "今夜")
        state.shownParticipationKeys = ["key"]
        state.firstMatchRecord.inviteCodeShared = true
        state.calendarPresented = true
        let store = makeStore(state)
        await store.send(.authenticationStateChanged(.authenticated(AuthenticationSession(userID: "user-2", accessToken: "access-2"))))
        #expect(store.state.composer == nil)
        #expect(store.state.reply == nil)
        #expect(store.state.sentInvitation == nil)
        #expect(store.state.participationBanner == nil)
        #expect(store.state.shownParticipationKeys.isEmpty)
        #expect(store.state.firstMatchRecord == FirstMatchRecord())
        #expect(!store.state.calendarPresented)
    }

    @Test("切り替え前のアカウントの送信結果は反映しない")
    func lateResultIgnored() async {
        let store = makeStore(signedInState(user: "user-2"))
        var created = AppSnapshot.empty()
        created.hostings = [makeHosting(range: TimeIntervalRange(start: t(1, 19), end: t(1, 22)))]
        await store.send(.hostingCreated(created, owner: "user-1"))
        #expect(store.state.sentInvitation == nil)
        #expect(store.state.snapshot?.hostings.isEmpty == true)
        await store.send(.responseFailed("失敗", owner: "user-1"))
        #expect(store.state.alertMessage == nil)
        await store.send(.hostingMutationCompleted(UUID(5), true, created, owner: "user-1"))
        #expect(store.state.snapshot?.hostings.isEmpty == true)
    }

    @Test("送信中はお誘い作成を閉じられず、再試行で同じ操作IDを使う")
    func closeWhileSubmittingIsIgnored() async {
        var composer = InvitationComposerFeature.State(
            start: .blank, friends: [tanaka], availability: [], candidates: [], lastMeeting: nil, now: now, operationID: UUID(7)
        )
        composer.isSubmitting = true
        var state = signedInState()
        state.composer = composer
        let store = makeStore(state)
        await store.send(.composer(.presented(.closeTapped)))
        await store.send(.composer(.presented(.delegate(.close))))
        #expect(store.state.composer?.operationID == UUID(7))
    }

    @Test("引き下げ更新は友達・暇・お誘いをまとめて再読み込みする")
    func pullToRefreshReloadsFriendships() async {
        var client = HimatchClient.productionPlaceholder
        client.loadAvailability = { [] }
        client.loadHostings = { ([], []) }
        let friendship = FriendshipSnapshot(inviteCode: nil, friends: [tanaka], requests: [])
        let store = makeStore(signedInState(), client: client) {
            $0.friendshipClient.load = { _ in friendship }
        }
        await store.send(.homeRefreshed)
        await store.receive(\.reloadFriendships)
        await store.receive(\.reloadAvailability)
        await store.receive(\.reloadHostings)
        await store.receive(\.friendshipsLoaded)
        #expect(store.state.snapshot?.friends == [tanaka])
    }
}
