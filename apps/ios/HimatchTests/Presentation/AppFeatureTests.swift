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
            $0.isLoading = true
        }
        await store.receive(\.friendshipsLoaded) {
            $0.snapshot?.apply(friendship)
            $0.isLoading = false
        }
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
            $0.homeTimeline.selection?.issue = .overlap(existing.id)
        }
        var withoutSlot = store.state.snapshot!
        withoutSlot.availability = []
        await store.send(.snapshotMutationCompleted(withoutSlot)) {
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
        await store.send(.homeTimeline(.quickSaveTapped))
        await store.receive(\.homeTimeline.delegate.quickSave) {
            $0.homeTimeline.selection?.isSaving = true
        }
        let slot = AvailabilitySlot(
            id: UUID(0),
            interval: TimeIntervalRange(id: UUID(0), start: date(3, 10, 0), end: date(3, 10, 45)),
            category: nil,
            visibility: .privateUntilAccepted
        )
        await store.receive(\.quickSaveSucceeded) {
            $0.snapshot?.availability = [slot]
            $0.homeTimeline.selection = nil
            $0.homeTimeline.lastSavedItem = .availability(UUID(0))
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
            $0.snapshot?.availability = [
                AvailabilitySlot(
                    id: UUID(1),
                    interval: TimeIntervalRange(id: UUID(1), start: picked.start, end: picked.end)
                )
            ]
            $0.homeTimeline.selection = nil
            $0.homeTimeline.lastSavedItem = .availability(UUID(1))
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
            $0.snapshot?.availability = [slot]
            $0.availabilityEditor = nil
            $0.homeTimeline.selection = nil
        }
        #expect(slot.interval.start == date(4, 23, 0))
        #expect(slot.interval.end == date(5, 0, 30))
    }

    @Test("重複した既存枠へ移動して詳細を表示する")
    func conflictNavigatesToExistingSlot() async {
        let existing = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(6, 11, 0), end: date(6, 13, 0))
        )
        let store = availabilityStore(availability: [existing])
        let picked = QuarterRange(start: date(6, 12, 0), end: date(6, 12, 15))

        await store.send(.homeTimeline(.quarterTapped(date(6, 12, 0)))) {
            $0.homeTimeline.today = self.date(1, 0, 0)
            $0.homeTimeline.selectedDayIndex = 5
            $0.homeTimeline.selection = .init(range: picked)
            $0.homeTimeline.selection?.issue = .overlap(existing.id)
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
        #expect(store.state.availabilityEditor?.issue == .overlap(existing.id))

        await store.send(.availabilityEditor(.presented(.conflictTapped(existing.id))))
        await store.receive(\.availabilityEditor.presented.delegate.showExistingSlot) {
            $0.availabilityEditor = nil
            $0.homeTimeline.selectedItem = .availability(existing.id)
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

    @Test("プロフィール保存結果を共有シナリオから取得できる")
    func profileCanBeSavedThroughInjectedBoundary() async throws {
        let scenario = HimatchPrototypeScenario(now: Date(timeIntervalSince1970: 2_000_000_000))
        let saved = try await scenario.client().saveProfile("テストユーザー", "star.fill")

        #expect(saved.profileName == "テストユーザー")
        #expect(saved.profileIcon == "star.fill")
    }
}
