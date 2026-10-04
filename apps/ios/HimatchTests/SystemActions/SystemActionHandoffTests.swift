import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("System action handoff")
struct SystemActionHandoffTests {
    @Test("認証失効で旧本人のSheetと準備済み操作を閉じる")
    func authenticationInvalidationClearsHandoff() async {
        let invalidated = HandoffOwnerRecorder()
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = .init(userID: "owner", accessToken: "token")
        state.systemActionOperationID = UUID()
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.systemActionHandoffClient = .init(pendingOperationID: { nil }, invalidate: { await invalidated.record($0) })
        }
        await store.send(.authenticationInvalidated("再認証してください。")) {
            $0.systemActionOperationID = nil
            $0.authenticationSession = nil
            $0.route = .onboarding
            $0.alertMessage = "再認証してください。"
        }
        await store.finish()
        #expect(await invalidated.owner == "owner")
    }

    @Test("認証前に操作画面を開かない")
    func handoffWaitsForAuthenticatedMainRoute() async {
        var state = AppFeature.State()
        state.route = .onboarding
        let store = TestStore(initialState: state) { AppFeature() }
        await store.send(.systemActionAvailable(UUID()))
        #expect(store.state.systemActionOperationID == nil)
    }

    @Test("同じ前面復帰通知で入力画面を上書きしない")
    func repeatedForegroundNotificationKeepsCurrentOperation() async {
        let id = UUID(), next = UUID()
        var state = AppFeature.State()
        state.route = .main
        let store = TestStore(initialState: state) { AppFeature() }
        await store.send(.systemActionAvailable(id)) { $0.systemActionOperationID = id }
        await store.send(.systemActionAvailable(next))
        #expect(store.state.systemActionOperationID == id)
        await store.send(.systemActionDismissed) { $0.systemActionOperationID = nil }
    }

    @Test("明示デモへSiriの実操作を引き継がない")
    func demoDoesNotReceiveSystemAction() async {
        var state = AppFeature.State(); state.route = .main; state.isDemo = true
        let store = TestStore(initialState: state) { AppFeature() }
        await store.send(.systemActionAvailable(UUID()))
        await store.send(.systemActionsForeground)
    }

    @Test("確認した本人と違うセッションで変更を送信しない")
    func productionClientBindsMutationToExpectedOwner() async throws {
        var authentication = AuthenticationClient.unconfigured("test")
        authentication.restoreSession = { AuthenticationSession(userID: "other", accessToken: "other-token") }
        let client = AppRuntime.productionBusiness(
            authentication: authentication,
            availability: BackendAvailabilityAdapter(baseURL: URL(string: "https://invalid.local/")!),
            hosting: BackendHostingAdapter(baseURL: URL(string: "https://invalid.local/")!),
            expectedUserID: "owner",
            includeAvailabilitySnapshot: false
        )
        let start = Date(timeIntervalSince1970: 2_000_000_700)
        await #expect(throws: SystemActionAccessError.accountChanged) {
            try await client.addAvailability(.init(interval: .init(start: start, end: start.addingTimeInterval(900))))
        }
        await #expect(throws: SystemActionAccessError.accountChanged) {
            try await client.createHosting(.init(mode: .online, start: start, duration: 900, friends: []))
        }
        await #expect(throws: SystemActionAccessError.accountChanged) {
            try await client.cancelHosting(UUID(), UUID(), 1)
        }
    }

    @Test("送信直前の退会停止でHTTP変更を行わない")
    func deletionGateRunsAtMutationDispatch() async throws {
        var authentication = AuthenticationClient.unconfigured("test")
        authentication.restoreSession = { AuthenticationSession(userID: "owner", accessToken: "owner-token") }
        let client = AppRuntime.productionBusiness(
            authentication: authentication,
            availability: BackendAvailabilityAdapter(baseURL: URL(string: "https://invalid.local/")!),
            hosting: BackendHostingAdapter(baseURL: URL(string: "https://invalid.local/")!),
            expectedUserID: "owner", includeAvailabilitySnapshot: false,
            accessGate: { throw SystemActionAccessError.accountStopped }
        )
        await #expect(throws: SystemActionAccessError.accountStopped) {
            try await client.subtractAvailability(.init(start: Date(), end: Date().addingTimeInterval(900)), UUID())
        }
    }
}

private actor HandoffOwnerRecorder {
    var owner: String?
    func record(_ value: String) { owner = value }
}
