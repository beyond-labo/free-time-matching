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
        #expect(state.availabilityVisibility == .privateUntilAccepted)
        #expect(!state.reminderEnabled)
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

    @Test("プロフィール保存結果を共有シナリオから取得できる")
    func profileCanBeSavedThroughInjectedBoundary() async throws {
        let scenario = HimatchPrototypeScenario(now: Date(timeIntervalSince1970: 2_000_000_000))
        let saved = try await scenario.client().saveProfile("テストユーザー", "star.fill")

        #expect(saved.profileName == "テストユーザー")
        #expect(saved.profileIcon == "star.fill")
    }
}
