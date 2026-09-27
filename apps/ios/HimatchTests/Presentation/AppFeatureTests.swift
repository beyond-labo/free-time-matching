import Foundation
import ComposableArchitecture
import Security
import Testing
@testable import Himatch

@MainActor
@Suite("App feature")
struct AppFeatureTests {
    @Test("初期状態はセッション復元とホームタブを示す")
    func initialRouteAndTab() {
        let state = AppFeature.State()

        #expect(state.route == .launching)
        #expect(state.selectedTab == .home)
        #expect(state.availabilityEditor == nil)
        #expect(state.homeTimeline.mode == .day)
        #expect(!state.reminderEnabled)
    }

    @Test("友達mutationの再試行は同じoperation IDを使う")
    func friendshipOperationIDIsStableForRetry() {
        var state = AppFeature.State()

        let first = state.operationID(forFriendshipKey: "accept:request:1")
        let retry = state.operationID(forFriendshipKey: "accept:request:1")
        let other = state.operationID(forFriendshipKey: "reject:request:1")

        #expect(first == retry)
        #expect(other != first)
    }

    @Test("復元プロフィールがある場合はメイン画面へ進む")
    func restoredProfileRoutesToMain() async {
        let profile = UserProfile(
            userID: "00000000-0000-0000-0000-000000000001",
            nickname: "ひまり",
            presetIcon: .sun
        )
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.profileLoaded(profile)) {
            $0.isLoading = false
            $0.profileName = "ひまり"
            $0.profileIcon = PresetProfileIcon.sun.rawValue
            $0.snapshot = .empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
            $0.route = .main
        }
    }

    @Test("削除状況の確認中はSDKの初期session eventでアクセスを復元しない")
    func initialAuthEventWaitsForDeletionCheck() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        let session = AuthenticationSession(userID: "user", accessToken: "access")

        await store.send(.authenticationStateChanged(.authenticated(session)))

        #expect(store.state.route == .launching)
        #expect(store.state.authenticationSession == nil)
    }

    @Test("STG友達snapshotの初回コードを認証後に表示状態へ反映する")
    func friendshipSnapshotLoadsIssuedCode() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "user", accessToken: "staging-access")
        state.snapshot = .empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
        let friendship = FriendshipSnapshot(
            inviteCode: InviteCode(
                value: "HIMA-ABCD-EFGH-JKMP-QRST",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            friends: [],
            requests: []
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.friendshipClient = FriendshipClient(
                load: { token in
                    #expect(token == "staging-access")
                    return friendship
                },
                rotateCode: { _ in friendship },
                resolveCode: { _, _ in throw BackendClientError.invalidResponse },
                sendRequest: { _, _, _ in friendship },
                transitionRequest: { _, _, _, _, _ in friendship },
                removeFriend: { _, _, _, _ in friendship }
            )
        }

        await store.send(.reloadFriendships) {
            $0.isFriendshipLoading = true
        }
        await store.receive(\.friendshipsLoaded) {
            $0.snapshot?.apply(friendship)
            $0.isFriendshipLoading = false
        }
        #expect(store.state.isLoading == false)
    }

    @Test("暇の初回GETはホーム全体を塞がず本人枠を反映する")
    func availabilityLoadIsPartial() async {
        let slot = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(3, 10, 0), end: date(3, 11, 0))
        )
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "owner", accessToken: "access")
        state.snapshot = .empty()
        var client = HimatchClient.productionPlaceholder
        client.loadAvailability = { [slot] in [slot] }
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
        }

        await store.send(.reloadAvailability) {
            $0.isAvailabilityLoading = true
        }
        await store.receive(\.availabilityLoaded) {
            $0.isAvailabilityLoading = false
            $0.snapshot?.availability = [slot]
        }
        #expect(store.state.isLoading == false)
    }

    @Test("認証拒否時はsessionと機密画面状態を破棄する")
    func authenticationRejectionClearsAuthenticatedState() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "user", accessToken: "access")
        state.snapshot = .empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.authenticationInvalidated("サインインし直してください。")) {
            $0.authenticationSession = nil
            $0.snapshot = nil
            $0.isDemo = false
            $0.isLoading = false
            $0.route = .onboarding
            $0.alertMessage = "サインインし直してください。"
        }
    }

    @Test("別sessionの友達応答は現在の画面状態へ反映しない")
    func staleFriendshipResponseIsIgnored() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "current-user", accessToken: "access")
        state.snapshot = .empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
        let stale = FriendshipSnapshot(
            inviteCode: InviteCode(
                value: "HIMA-ABCD-EFGH-JKMP-QRST",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            friends: [],
            requests: []
        )
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.friendshipsLoaded(stale, userID: "previous-user"))

        #expect(store.state.snapshot?.inviteCode == nil)
    }

    @Test("削除受付結果はセッションを停止して状態を保持する")
    func deletionResultStopsLocalAccess() async {
        var state = AppFeature.State()
        state.authenticationSession = AuthenticationSession(userID: "user", accessToken: "access")
        state.deletionOperationID = UUID()
        let store = TestStore(initialState: state) { AppFeature() }
        let receipt = AccountDeletionReceipt(
            reference: "DEL-42",
            status: .actionRequired,
            statusToken: "status-token",
            message: "再試行してください"
        )

        await store.send(.deletionSubmitted(receipt)) {
            $0.accountDeletionReceipt = receipt
            $0.deletionOperationID = nil
            $0.authenticationSession = nil
            $0.snapshot = .empty()
            $0.snapshot?.deletionStatus = .actionRequired(reference: "DEL-42", message: "再試行してください")
            $0.deleteConfirmationPresented = false
            $0.isLoading = false
            $0.route = .deletionAccepted
        }
    }

    @Test("削除受付後のKeychain失敗でもローカルアクセスを停止する")
    func keychainFailureAfterDeletionReceiptStillStopsAccess() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "user", accessToken: "access")
        state.deletionOperationID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")
        let receipt = AccountDeletionReceipt(
            reference: "DEL-KEYCHAIN",
            status: .actionRequired,
            statusToken: "status-token",
            message: "運用対応中です。"
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.accountDeletionClient = AccountDeletionClient(
                submit: { _ in receipt },
                status: { _ in receipt }
            )
            $0.authenticationClient = AuthenticationClient(
                restoreSession: { nil },
                signInWithApple: { _ in throw AuthenticationFailure.invalidAppleCredential },
                signOut: {},
                stateChanges: { AsyncStream { $0.finish() } }
            )
            $0.deletionStatusTokenStore = DeletionStatusTokenStore(
                save: { _ in throw KeychainTokenError.status(errSecNotAvailable) },
                load: { nil },
                remove: {}
            )
        }
        let credential = AppleAuthorizationCredential(
            identityToken: "identity-token",
            authorizationCode: "authorization-code",
            rawNonce: "raw-nonce"
        )

        await store.send(.deleteAccountAuthorized(credential)) {
            $0.isLoading = true
        }
        await store.receive(\.deletionSubmitted) {
            $0.accountDeletionReceipt = AccountDeletionReceipt(
                reference: receipt.reference,
                status: .actionRequired,
                statusToken: receipt.statusToken,
                message: "運用対応中です。 削除状況を端末へ保存できませんでした。受付番号を控えてください。"
            )
            $0.deletionOperationID = nil
            $0.authenticationSession = nil
            $0.snapshot = .empty()
            $0.snapshot?.deletionStatus = .actionRequired(
                reference: receipt.reference,
                message: "運用対応中です。 削除状況を端末へ保存できませんでした。受付番号を控えてください。"
            )
            $0.deleteConfirmationPresented = false
            $0.isLoading = false
            $0.route = .deletionAccepted
        }
    }

    @Test("起動時に保留中の削除状況を照会して削除受付画面を復元する")
    func restoresPendingDeletionOnLaunch() async {
        let pending = PendingAccountDeletion(reference: "DEL-42", statusToken: "status-token")
        let receipt = AccountDeletionReceipt(
            reference: pending.reference,
            status: .actionRequired,
            statusToken: pending.statusToken,
            message: "追加対応が必要です"
        )
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authenticationClient = AuthenticationClient(
                restoreSession: { Issue.record("保留中の削除がある場合は認証を復元しない"); return nil },
                signInWithApple: { _ in throw AuthenticationFailure.invalidAppleCredential },
                signOut: {},
                stateChanges: { AsyncStream { $0.finish() } }
            )
            $0.accountDeletionClient = AccountDeletionClient(
                submit: { _ in throw BackendClientError.invalidResponse },
                status: { value in
                    #expect(value == pending)
                    return receipt
                }
            )
            $0.deletionStatusTokenStore = DeletionStatusTokenStore(
                save: { _ in },
                load: { pending },
                remove: {}
            )
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        await store.receive(\.pendingDeletionRestored) {
            $0.accountDeletionReceipt = receipt
            $0.authenticationSession = nil
            $0.snapshot = .empty()
            $0.snapshot?.deletionStatus = .actionRequired(
                reference: pending.reference,
                message: "追加対応が必要です"
            )
            $0.isLoading = false
            $0.route = .deletionAccepted
        }
    }

    @Test("処理中の削除状況を追加対応必要と混同しない")
    func restoresProcessingDeletionStatus() async {
        let receipt = AccountDeletionReceipt(
            reference: "DEL-PROCESSING",
            status: .processing,
            statusToken: "status-token",
            message: nil
        )
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

        await store.send(.pendingDeletionRestored(receipt)) {
            $0.accountDeletionReceipt = receipt
            $0.authenticationSession = nil
            $0.snapshot = .empty()
            $0.snapshot?.deletionStatus = .processing(reference: receipt.reference)
            $0.isLoading = false
            $0.route = .deletionAccepted
        }
    }

    @Test("結果不明の削除操作は再起動後も同じoperation IDを復元する")
    func restoresAmbiguousDeletionOperation() async {
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let session = AuthenticationSession(userID: "user", accessToken: "access")
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authenticationClient = AuthenticationClient(
                restoreSession: { session },
                signInWithApple: { _ in throw AuthenticationFailure.invalidAppleCredential },
                signOut: {},
                stateChanges: { AsyncStream { $0.finish() } }
            )
            $0.deletionStatusTokenStore = DeletionStatusTokenStore(
                save: { _ in },
                load: { nil },
                remove: {},
                loadOperationID: { operationID }
            )
        }

        await store.send(.task) { $0.isLoading = true }
        await store.receive(\.deletionAttemptRestored) {
            $0.deletionOperationID = operationID
            $0.authenticationSession = session
            $0.snapshot = .empty()
            $0.deletionRecoveryMessage = "前回の削除要求は結果が不明です。Appleで再認証すると同じ操作IDで安全に再送できます。"
            $0.isLoading = false
            $0.route = .deletionAccepted
        }
    }

    @Test("カレンダーのタップは15分を選ぶだけでエディタを開かず、詳細調整で範囲をそのまま引き継ぐ")
    func calendarSelectionHandsExactRangeToEditor() async {
        let existing = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(2, 10, 0), end: date(2, 12, 0))
        )
        let store = availabilityStore(availability: [existing])

        await store.send(.homeTimeline(.quarterTapped(date(3, 10, 7)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selectedDayIndex = 2
            $0.homeTimeline.selection = .init(range: QuarterRange(start: self.date(3, 10, 0), end: self.date(3, 10, 15)))
        }
        #expect(store.state.availabilityEditor == nil)
        await store.send(.homeTimeline(.selectionEdgeStepped(.end, quarters: 2))) {
            $0.homeTimeline.selection = .init(range: QuarterRange(start: self.date(3, 10, 0), end: self.date(3, 10, 45)))
        }
        await store.send(.homeTimeline(.adjustDetailsTapped))
        await store.receive(\.homeTimeline.delegate.adjustSelection) {
            $0.availabilityEditor = AvailabilityEditorFeature.State(
                range: QuarterRange(start: self.date(3, 10, 0), end: self.date(3, 10, 45)),
                now: AvailabilityTestClock.now,
                calendar: AvailabilityTestClock.calendar,
                existing: [existing],
                slotID: UUID(0)
            )
        }
        #expect(store.state.availabilityEditor?.start == date(3, 10, 0))
        #expect(store.state.availabilityEditor?.end == date(3, 10, 45))
        #expect(store.state.availabilityEditor?.category == nil)
        #expect(store.state.availabilityEditor?.visibility == .privateUntilAccepted)
        #expect(store.state.homeTimeline.selection != nil)
    }

    @Test("過去・重複・14日範囲外の選択は選んだ時点で理由を付け、枠が消えると理由も消える")
    func selectionIssuesAreShownImmediately() async {
        let existing = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(3, 10, 0), end: date(3, 12, 0))
        )
        let store = availabilityStore(availability: [existing])

        await store.send(.homeTimeline(.quarterTapped(date(1, 9, 50)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selection = .init(range: QuarterRange(start: self.date(1, 9, 45), end: self.date(1, 10, 0)))
            $0.homeTimeline.selection?.issue = .past
        }
        #expect(store.state.homeTimeline.selection?.canQuickSave == false)

        await store.send(.homeTimeline(.quarterTapped(date(3, 11, 0)))) {
            $0.homeTimeline.selectedDayIndex = 2
            $0.homeTimeline.selection = .init(range: QuarterRange(start: self.date(3, 11, 0), end: self.date(3, 11, 15)))
        }
        #expect(store.state.homeTimeline.selection?.issue == nil)
        var withoutSlot = store.state.snapshot!
        withoutSlot.availability = []
        await store.send(.snapshotMutationCompleted(withoutSlot)) {
            $0.availabilityRevision = 1
            $0.snapshot = withoutSlot
            $0.homeTimeline.selection?.issue = nil
        }
    }

    @Test("14日範囲を越える選択は登録できない理由を付ける")
    func outOfWindowSelectionIsMarked() async {
        let store = availabilityStore(selection: QuarterRange(start: date(15, 11, 0), end: date(15, 11, 15)))

        await store.send(.homeTimeline(.itemDismissed)) {
            $0.homeTimeline.selection?.issue = .outsideWindow
        }
    }

    @Test("非公開で登録はカテゴリ未選択・非公開で選択範囲どおりに保存し、選択を消す")
    func quickSaveRegistersPrivateSlot() async {
        let saved = LockIsolated<AvailabilitySlot?>(nil)
        let store = availabilityStore(addAvailability: { slot in
            saved.setValue(slot)
            var snapshot = AppSnapshot.empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
            snapshot.availability = [slot]
            return snapshot
        })

        await store.send(.homeTimeline(.rangeSelectionChanged(anchor: date(3, 10, 40), focus: date(3, 10, 0)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selectedDayIndex = 2
            $0.homeTimeline.selection = .init(range: QuarterRange(start: self.date(3, 10, 0), end: self.date(3, 10, 45)))
        }
        let operationID = store.state.homeTimeline.selection!.operationID
        await store.send(.homeTimeline(.quickSaveTapped))
        await store.receive(\.homeTimeline.delegate.quickSave) {
            $0.homeTimeline.selection?.isSaving = true
        }
        let slot = AvailabilitySlot(
            id: operationID,
            interval: TimeIntervalRange(id: operationID, start: date(3, 10, 0), end: date(3, 10, 45)),
            category: nil,
            visibility: .privateUntilAccepted
        )
        await store.receive(\.quickSaveSucceeded) {
            $0.availabilityRevision = 1
            $0.snapshot?.availability = [slot]
            $0.homeTimeline.selection = nil
            $0.homeTimeline.lastSavedItem = .availability(operationID)
            $0.homeTimeline.quickSaveSuccessCount = 1
        }
        #expect(saved.value == slot)
    }

    @Test("登録に失敗しても選択を保持し、再試行で登録できる")
    func quickSaveFailureKeepsSelectionForRetry() async {
        let attempts = LockIsolated(0)
        let store = availabilityStore(addAvailability: { slot in
            attempts.withValue { $0 += 1 }
            if attempts.value == 1 { throw PrototypeError.notFound }
            var snapshot = AppSnapshot.empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
            snapshot.availability = [slot]
            return snapshot
        })
        let picked = QuarterRange(start: date(4, 20, 0), end: date(4, 20, 15))

        await store.send(.homeTimeline(.quarterTapped(date(4, 20, 5)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selectedDayIndex = 3
            $0.homeTimeline.selection = .init(range: picked)
        }
        let operationID = store.state.homeTimeline.selection!.operationID
        await store.send(.homeTimeline(.quickSaveTapped))
        await store.receive(\.homeTimeline.delegate.quickSave) {
            $0.homeTimeline.selection?.isSaving = true
        }
        await store.receive(\.quickSaveFailed) {
            $0.homeTimeline.selection?.isSaving = false
            $0.homeTimeline.selection?.saveError = PrototypeError.notFound.errorDescription
        }
        #expect(store.state.homeTimeline.selection?.range == picked)

        await store.send(.homeTimeline(.quickSaveTapped))
        await store.receive(\.homeTimeline.delegate.quickSave) {
            $0.homeTimeline.selection?.isSaving = true
            $0.homeTimeline.selection?.saveError = nil
        }
        await store.receive(\.quickSaveSucceeded) {
            $0.availabilityRevision = 1
            $0.snapshot?.availability = [
                AvailabilitySlot(
                    id: operationID,
                    interval: TimeIntervalRange(id: operationID, start: picked.start, end: picked.end)
                )
            ]
            $0.homeTimeline.selection = nil
            $0.homeTimeline.lastSavedItem = .availability(operationID)
            $0.homeTimeline.quickSaveSuccessCount = 1
        }
        #expect(attempts.value == 2)
    }

    @Test("登録直前に開始時刻を過ぎていたら保存せず理由を表示する")
    func quickSaveRevalidatesBeforeSaving() async {
        let store = availabilityStore()

        await store.send(.homeTimeline(.quarterTapped(date(1, 10, 15)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selection = .init(range: QuarterRange(start: self.date(1, 10, 15), end: self.date(1, 10, 30)))
        }
        store.dependencies.date = .constant(date(1, 10, 16))
        await store.send(.homeTimeline(.quickSaveTapped)) {
            $0.homeTimeline.selection?.issue = .past
        }
        await store.receive(\.homeTimeline.delegate.quickSave)
    }

    @Test("14日範囲外の位置からは開始せず理由を表示する")
    func outOfWindowAnchorShowsAlert() async {
        let store = availabilityStore()

        await store.send(.homeTimeline(.delegate(.startAvailability(anchor: AvailabilityTestClock.date(day: 20, hour: 9, minute: 0))))) {
            $0.alertMessage = "この時間からは登録できません。今後14日以内の時間を選んでください。"
        }
    }

    @Test("前回の共有設定は次の新規枠へ引き継がない")
    func visibilityResetsForNextEditor() async {
        let store = availabilityStore()

        await store.send(.homeTimeline(.newAvailabilityTapped))
        await store.receive(\.homeTimeline.delegate.startAvailability) {
            $0.availabilityEditor = AvailabilityEditorFeature.State(
                anchor: nil,
                now: AvailabilityTestClock.now,
                calendar: AvailabilityTestClock.calendar,
                existing: [],
                slotID: UUID(0)
            )
        }
        await store.send(.availabilityEditor(.presented(.visibilityChanged(.shareOnHosting)))) {
            $0.availabilityEditor?.visibility = .shareOnHosting
        }
        await store.send(.availabilityEditor(.dismiss)) {
            $0.availabilityEditor = nil
        }
        await store.send(.homeTimeline(.newAvailabilityTapped))
        await store.receive(\.homeTimeline.delegate.startAvailability) {
            $0.availabilityEditor = AvailabilityEditorFeature.State(
                anchor: nil,
                now: AvailabilityTestClock.now,
                calendar: AvailabilityTestClock.calendar,
                existing: [],
                slotID: UUID(1)
            )
        }
        #expect(store.state.availabilityEditor?.visibility == .privateUntilAccepted)
    }

    @Test("詳細調整から保存するとエディタと選択を閉じ、登録した日を表示する")
    func editorSaveFromSelectionClearsSelection() async {
        let store = availabilityStore(addAvailability: { slot in
            var snapshot = AppSnapshot.empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
            snapshot.availability = [slot]
            return snapshot
        })
        let picked = QuarterRange(start: date(4, 23, 0), end: date(5, 0, 0))

        await store.send(.homeTimeline(.rangeSelectionChanged(anchor: date(4, 23, 0), focus: date(4, 23, 50)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selectedDayIndex = 3
            $0.homeTimeline.selection = .init(range: picked)
        }
        await store.send(.homeTimeline(.adjustDetailsTapped))
        await store.receive(\.homeTimeline.delegate.adjustSelection) {
            $0.availabilityEditor = AvailabilityEditorFeature.State(
                range: picked,
                now: AvailabilityTestClock.now,
                calendar: AvailabilityTestClock.calendar,
                existing: [],
                slotID: UUID(0)
            )
        }
        // Overnight extension happens in the editor, not on the one-day grid.
        await store.send(.availabilityEditor(.presented(.endStepped(quarters: 2)))) {
            $0.availabilityEditor?.end = self.date(5, 0, 30)
        }
        let slot = store.state.availabilityEditor!.slot
        await store.send(.availabilityEditor(.presented(.saveTapped))) {
            $0.availabilityEditor?.isSaving = true
        }
        await store.receive(\.availabilityEditor.presented.saveSucceeded) {
            $0.availabilityEditor?.isSaving = false
        }
        await store.receive(\.availabilityEditor.presented.delegate.saved) {
            $0.availabilityRevision = 1
            $0.snapshot?.availability = [slot]
            $0.availabilityEditor = nil
            $0.homeTimeline.selection = nil
        }
        #expect(slot.interval.start == date(4, 23, 0))
        #expect(slot.interval.end == date(5, 0, 30))
    }

    @Test("重複選択は既存枠の詳細編集からOR統合できる")
    func overlappingSelectionOpensUnionEditor() async {
        let existing = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(6, 11, 0), end: date(6, 13, 0)),
            category: .game
        )
        let store = availabilityStore(availability: [existing])
        let picked = QuarterRange(start: date(6, 12, 0), end: date(6, 12, 15))

        await store.send(.homeTimeline(.quarterTapped(date(6, 12, 0)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selectedDayIndex = 5
            $0.homeTimeline.selection = .init(range: picked)
        }
        await store.send(.homeTimeline(.adjustDetailsTapped))
        await store.receive(\.homeTimeline.delegate.adjustSelection) {
            $0.availabilityEditor = AvailabilityEditorFeature.State(
                range: picked,
                now: AvailabilityTestClock.now,
                calendar: AvailabilityTestClock.calendar,
                existing: [existing],
                slotID: UUID(0)
            )
        }
        #expect(store.state.availabilityEditor?.issue == nil)
        #expect(store.state.availabilityEditor?.hasConflictingMetadata == true)
    }

    @Test("募集中の時間を削除しようとすると取消できる受信箱へ案内する")
    func deletingRecruitingRangeOpensCancellationInbox() async {
        let active = Hosting(
            id: UUID(7),
            mode: .online,
            area: nil,
            category: nil,
            candidateRange: TimeIntervalRange(start: date(3, 10, 15), end: date(3, 11, 0)),
            requiredDuration: 0,
            friends: [],
            participants: [],
            status: .recruiting
        )
        var state = AppFeature.State()
        state.route = .main
        state.isDemo = true
        state.snapshot = .empty()
        state.snapshot?.hostings = [active]
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.date.now = AvailabilityTestClock.now
            $0.calendar = AvailabilityTestClock.calendar
        }
        let selected = QuarterRange(start: date(3, 10, 0), end: date(3, 10, 30))

        await store.send(.homeTimeline(.delegate(.subtractAvailability(selected, UUID(8))))) {
            $0.alertMessage = "募集中の時間は削除できません。受信箱で募集を取り消してから、もう一度削除してください。"
        }
        await store.receive(\.showInbox) { $0.inboxPresented = true }
    }

    @Test("DBが募集中競合を返した場合も取消Inboxへ案内する")
    func databaseRecruitingConflictOpensCancellationInbox() async {
        let selected = QuarterRange(start: date(3, 10, 0), end: date(3, 10, 30))
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "owner", accessToken: "access")
        state.snapshot = .empty()
        state.homeTimeline.today = date(1, 0, 0)
        state.homeTimeline.selection = .init(range: selected)
        var client = HimatchClient.productionPlaceholder
        client.subtractAvailability = { _, _ in throw BackendClientError.response(409, "active hosting") }
        client.loadHostings = { ([], []) }
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.date.now = AvailabilityTestClock.now
            $0.calendar = AvailabilityTestClock.calendar
            $0.himatchClient = client
        }

        await store.send(.homeTimeline(.delegate(.subtractAvailability(selected, UUID(9))))) {
            $0.homeTimeline.selection?.isSaving = true
        }
        await store.receive(\.availabilityDeletionBlocked) {
            $0.homeTimeline.selection?.isSaving = false
            $0.alertMessage = "募集中の時間は削除できません。受信箱で募集を取り消してから、もう一度削除してください。"
        }
        await store.receive(\.showInbox) { $0.inboxPresented = true }
        await store.receive(\.hostingLoadCompleted)
    }

    @Test("募集作成は選んだ全員と正確な範囲を送信し、成功後に募集中一覧へ反映する")
    func hostingCreationSendsSelectedFriendsAndRange() async {
        let friend = FriendProfile(id: UUID(21), displayName: "りく", icon: "figure.run")
        let secondFriend = FriendProfile(id: UUID(24), displayName: "さき", icon: "sun.max.fill")
        let hostingID = UUID(22)
        let operationID = UUID(23)
        let start = date(4, 10, 0)
        let end = date(4, 10, 45)
        let hosting = Hosting(
            id: hostingID,
            mode: .offline,
            area: .shibuya,
            category: .game,
            candidateRange: TimeIntervalRange(id: hostingID, start: start, end: end),
            requiredDuration: end.timeIntervalSince(start),
            friends: [friend], participants: [], status: .recruiting
        )
        let receivedDraft = LockIsolated<HostingDraft?>(nil)
        var returned = AppSnapshot.empty(profileName: "ひまり")
        returned.hostings = [hosting]
        let creationResponse = returned
        var client = HimatchClient.productionPlaceholder
        client.createHosting = { draft in
            receivedDraft.setValue(draft)
            return creationResponse
        }
        var state = AppFeature.State()
        state.route = .main
        state.snapshot = .empty(profileName: "ひまり")
        state.snapshot?.friends = [friend, secondFriend]
        state.hostingEditorPresented = true
        state.hostingStart = start
        state.hostingEnd = end
        state.hostingOperationID = operationID
        state.selectedFriendIDs = [friend.id, secondFriend.id]
        state.hostingAvailabilityConflict = true
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
        }

        await store.send(.createHostingTapped)
        #expect(receivedDraft.value == nil)
        await store.send(.confirmHostingAvailabilityMetadata) {
            $0.hostingAvailabilityMetadataConfirmed = true
        }
        await store.send(.createHostingTapped) { $0.isLoading = true }
        await store.receive(\.hostingCreated) {
            $0.hostingRevision = 1
            $0.snapshot = creationResponse
            $0.hostingEditorPresented = false
            $0.hostingOperationID = nil
            $0.selectedFriendIDs = []
            $0.homeTimeline.selection = nil
            $0.isLoading = false
            $0.alertMessage = "募集を開始しました。参加OKの回答があると、ここに表示されます。"
        }
        #expect(receivedDraft.value?.operationID == operationID)
        #expect(receivedDraft.value?.start == start)
        #expect(receivedDraft.value?.duration == end.timeIntervalSince(start))
        #expect(receivedDraft.value?.friends == [friend, secondFriend])
        #expect(store.state.snapshot?.hostings == [hosting])
    }

    @Test("招待送信失敗後も範囲・友達・operation IDを保持して再試行可能にする")
    func hostingCreationFailureKeepsDraft() async {
        let friend = FriendProfile(id: UUID(31), displayName: "りく", icon: "figure.run")
        let operationID = UUID(32)
        let start = date(4, 10, 0)
        var client = HimatchClient.productionPlaceholder
        client.createHosting = { _ in throw BackendClientError.response(503, "一時エラー") }
        var state = AppFeature.State()
        state.route = .main
        state.snapshot = .empty(profileName: "ひまり")
        state.snapshot?.friends = [friend]
        state.hostingEditorPresented = true
        state.hostingStart = start
        state.hostingEnd = start.addingTimeInterval(2700)
        state.hostingOperationID = operationID
        state.selectedFriendIDs = [friend.id]
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
        }

        await store.send(.createHostingTapped) { $0.isLoading = true }
        await store.receive(\.hostingCreationFailed) {
            $0.isLoading = false
            $0.alertMessage = "募集を送信できませんでした。入力内容は保持しています。\n一時エラー"
        }
        #expect(store.state.hostingEditorPresented)
        #expect(store.state.hostingStart == start)
        #expect(store.state.hostingEnd == start.addingTimeInterval(2700))
        #expect(store.state.selectedFriendIDs == [friend.id])
        #expect(store.state.hostingOperationID == operationID)
    }

    @Test("招待者の部分参加OKを範囲付きで送り、返却projectionへ更新する")
    func invitationAcceptsOnlySelectedPartialRange() async {
        let id = UUID(41)
        let host = FriendProfile(id: UUID(42), displayName: "さき", icon: "figure.run")
        let start = date(5, 10, 0)
        let candidate = TimeIntervalRange(id: id, start: start, end: start.addingTimeInterval(3600))
        let partial = TimeIntervalRange(start: start.addingTimeInterval(900), end: start.addingTimeInterval(2700))
        let pending = Hosting(
            id: id, mode: .online, area: nil, category: .game,
            candidateRange: candidate, requiredDuration: 3600,
            friends: [], participants: [], status: .recruiting, version: 1,
            myInvitation: HostingInvitation(status: .pending, version: 1, intervals: nil),
            isHostedByMe: false, host: host
        )
        let accepted = Hosting(
            id: id, mode: .online, area: nil, category: .game,
            candidateRange: candidate, requiredDuration: 3600,
            friends: [], participants: [], status: .recruiting, version: 2,
            myInvitation: HostingInvitation(status: .accepted, version: 2, intervals: [partial]),
            isHostedByMe: false, host: host
        )
        let operationID = UUID(43)
        let responseKey = "\(id.uuidString)|1|accepted|\(partial.start.timeIntervalSince1970):\(partial.end.timeIntervalSince1970)"
        let captured = LockIsolated<([TimeIntervalRange], UUID, Int)?>(nil)
        var responseSnapshot = AppSnapshot.empty()
        responseSnapshot.invitations = [accepted]
        let acceptedResponse = responseSnapshot
        var client = HimatchClient.productionPlaceholder
        client.respondInvitation = { hostingID, status, intervals, opID, version in
            #expect(hostingID == id)
            #expect(status == .accepted)
            captured.setValue((intervals, opID, version))
            return acceptedResponse
        }
        var state = AppFeature.State()
        state.route = .main
        state.isDemo = true
        state.snapshot = .empty()
        state.snapshot?.invitations = [pending]
        state.hostingResponseOperationIDs[responseKey] = operationID
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
        }

        await store.send(.respondToInvitation(id, .accepted, [partial])) { $0.isLoading = true }
        await store.receive(\.hostingMutationCompleted) {
            $0.isLoading = false
            $0.hostingRevision = 1
            $0.snapshot?.invitations = [accepted]
            $0.hostingResponseOperationIDs = [:]
        }
        await store.receive(\.showInbox) { $0.inboxPresented = true }
        #expect(captured.value?.0 == [partial])
        #expect(captured.value?.1 == operationID)
        #expect(captured.value?.2 == 1)
        #expect(store.state.snapshot?.invitations.first?.myInvitation?.intervals == [partial])
    }

    @Test("認証後の初回Hosting取得をtimeline projectionへ反映する")
    func initialHostingLoadProjectsIntoSnapshot() async {
        let hosting = Hosting(
            id: UUID(51), mode: .online, area: nil, category: nil,
            candidateRange: TimeIntervalRange(start: date(3, 10, 0), end: date(3, 11, 0)),
            requiredDuration: 3600, friends: [], participants: [], status: .recruiting
        )
        let invitation = Hosting(
            id: UUID(52), mode: .online, area: nil, category: nil,
            candidateRange: TimeIntervalRange(start: date(4, 10, 0), end: date(4, 11, 0)),
            requiredDuration: 3600, friends: [], participants: [], status: .recruiting,
            myInvitation: HostingInvitation(status: .pending, version: 1, intervals: nil),
            isHostedByMe: false, host: FriendProfile(id: UUID(53), displayName: "さき", icon: "figure.run")
        )
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "owner", accessToken: "token")
        state.snapshot = .empty()
        var client = HimatchClient.productionPlaceholder
        client.loadHostings = { ([hosting], [invitation]) }
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.himatchClient = client
        }

        await store.send(.reloadHostings)
        await store.receive(\.hostingLoadCompleted) {
            $0.snapshot?.hostings = [hosting]
            $0.snapshot?.invitations = [invitation]
        }
        #expect(store.state.snapshot?.hostings == [hosting])
        #expect(store.state.snapshot?.invitations == [invitation])

        var postMutation = store.state
        postMutation.hostingRevision = 1
        let guardedStore = TestStore(initialState: postMutation) { AppFeature() }
        let stale = Hosting(
            id: UUID(54), mode: .online, area: nil, category: nil,
            candidateRange: TimeIntervalRange(start: date(6, 10, 0), end: date(6, 11, 0)),
            requiredDuration: 3600, friends: [], participants: [], status: .recruiting
        )
        await guardedStore.send(.hostingLoadCompleted([stale], [], revision: 0, userID: "owner"))
        #expect(guardedStore.state.snapshot?.hostings == [hosting])
    }

    @Test("招待時刻の編集は候補終端と冪等operation IDを更新する")
    func hostingTimeEditsRotateOperationIDAndKeepRangeCoherent() async {
        var state = AppFeature.State()
        state.hostingStart = date(4, 10, 0)
        state.hostingEnd = date(4, 10, 30)
        state.hostingOperationID = UUID(61)
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.hostingStartChanged(date(4, 11, 0))) {
            $0.hostingStart = self.date(4, 11, 0)
            $0.hostingEnd = self.date(4, 11, 30)
            $0.hostingOperationID = UUID(0)
        }
        await store.send(.hostingDurationChanged(2)) {
            $0.hostingDurationHours = 2
            $0.hostingEnd = self.date(4, 13, 0)
            $0.hostingOperationID = UUID(1)
        }
    }

    @Test("複数暇枠の募集統合は属性確認を必須とし、設定変更で再確認を求める")
    func hostingMetadataConflictRequiresConfirmation() async {
        var state = AppFeature.State()
        state.snapshot = .empty()
        state.snapshot?.availability = [
            AvailabilitySlot(
                interval: TimeIntervalRange(start: date(4, 10, 0), end: date(4, 11, 0)),
                category: .game
            ),
            AvailabilitySlot(
                interval: TimeIntervalRange(start: date(4, 11, 0), end: date(4, 12, 0)),
                category: .meal
            ),
        ]
        state.hostingStart = date(4, 10, 30)
        state.hostingEnd = date(4, 11, 30)
        state.hostingOperationID = UUID(71)
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.hostingAvailabilityCategoryChanged(.game)) {
            $0.hostingAvailabilityCategory = .game
            $0.hostingOperationID = UUID(0)
            $0.hostingAvailabilityConflict = true
        }
        await store.send(.confirmHostingAvailabilityMetadata) {
            $0.hostingAvailabilityMetadataConfirmed = true
        }
        await store.send(.hostingAvailabilityVisibilityChanged(.shareOnHosting)) {
            $0.hostingAvailabilityVisibility = .shareOnHosting
            $0.hostingOperationID = UUID(1)
            $0.hostingAvailabilityMetadataConfirmed = false
            $0.hostingAvailabilityConflict = true
        }
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        AvailabilityTestClock.date(day: day, hour: hour, minute: minute)
    }

    private func availabilityStore(
        selection: QuarterRange? = nil,
        availability: [AvailabilitySlot] = [],
        addAvailability: @escaping @Sendable (AvailabilitySlot) async throws -> AppSnapshot = { _ in
            Issue.record("保存は呼ばれない想定")
            return .empty()
        }
    ) -> TestStoreOf<AppFeature> {
        var state = AppFeature.State()
        state.route = .main
        state.snapshot = .empty(profileName: "ひまり", profileIcon: PresetProfileIcon.sun.rawValue)
        state.snapshot?.availability = availability
        if let selection {
            state.homeTimeline.today = date(1, 0, 0)
            state.homeTimeline.selectedDayIndex = 13
            state.homeTimeline.selection = .init(range: selection)
        }
        var client = HimatchClient.productionPlaceholder
        client.addAvailability = addAvailability
        return TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.date.now = AvailabilityTestClock.now
            $0.calendar = AvailabilityTestClock.calendar
            $0.uuid = .incrementing
            $0.himatchClient = client
        }
    }

    @Test("保存後に届いた古い本人枠GETは登録結果を上書きしない")
    func staleAvailabilityLoadDoesNotOverwriteSave() async {
        let saved = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(3, 10, 0), end: date(3, 11, 0))
        )
        var state = AppFeature.State()
        state.route = .main
        state.snapshot = .empty(availability: [saved])
        state.authenticationSession = AuthenticationSession(userID: "owner", accessToken: "access")
        state.availabilityRevision = 1
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.availabilityLoaded([], revision: 0, userID: "owner"))
        await store.send(.availabilityLoaded([], revision: 1, userID: "other"))
        #expect(store.state.snapshot?.availability == [saved])
    }

    @Test("プロフィール保存結果を共有シナリオから取得できる")
    func profileCanBeSavedThroughInjectedBoundary() async throws {
        let scenario = HimatchPrototypeScenario(now: Date(timeIntervalSince1970: 2_000_000_000))
        let saved = try await scenario.client().saveProfile("テストユーザー", "star.fill")

        #expect(saved.profileName == "テストユーザー")
        #expect(saved.profileIcon == "star.fill")
    }
}
