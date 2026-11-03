import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("Automatic scheduling state")
struct AutomaticSchedulingFeatureTests {
    @Test("同じアカウントへの再ログインでも旧応答とrevisionが再一致しない")
    func logoutPreservesSchedulingGeneration() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = .init(userID: "owner", accessToken: "token")
        state.automaticScheduling.ownerID = "owner"
        state.automaticScheduling.revision = 5
        state.automaticScheduling.snapshot = .empty
        let store = TestStore(initialState: state) { AppFeature() }
        await store.send(.logoutCompleted) {
            $0 = .init()
            $0.automaticScheduling.revision = 6
            $0.route = .onboarding
        }
    }

    @Test("通知登録からの認証失効でも匿名提案を破棄する")
    func notificationsCannotRetainExpiredSessionData() async {
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"
        state.snapshot = .empty
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() } withDependencies: {
            $0.automaticSchedulingEffects.requestNotifications = { _ in throw SchedulingFailure.unauthorized }
        }
        await store.send(.requestNotifications) { $0.isRegisteringNotifications = true }
        await store.receive(\.notificationsFailed) {
            $0.isRegisteringNotifications = false
            $0.snapshot = nil
            $0.error = SchedulingFailure.unauthorized.localizedDescription
        }
        await store.receive(\.delegate)
    }

    @Test("初期off、友達別許可なし、OK共有なし")
    func initialPrivacy() {
        let state = AutomaticSchedulingFeature.State()
        #expect(state.snapshot == nil)
        #expect(state.shareAcceptance.isEmpty)
        #expect(!SchedulingSnapshot.empty.enabled)
        #expect(!SchedulingSnapshot.empty.permits(UUID()))
        #expect(!state.canMutate)
    }

    @Test("結果不明の再試行は同じ操作IDと内容を使い、送信中の別操作を止める")
    func retryMaintainsOperation() async {
        let recorder = SchedulingOperationRecorder()
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000099")!
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"
        state.snapshot = .empty
        var result = SchedulingSnapshot.empty
        result.enabled = true
        let saved = result
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() } withDependencies: {
            $0.uuid = .constant(id)
            $0.automaticSchedulingEffects.execute = { command, operationID, owner in
                #expect(owner == "owner")
                let count = await recorder.record(command, operationID)
                if count == 1 { throw SchedulingFailure.unavailable }
                return saved
            }
        }
        await store.send(.send(.settings(true))) {
            $0.pendingCommand = .settings(true)
            $0.operationID = id
            $0.revision = 1
            $0.isSending = true
        }
        await store.receive(\.failed) {
            $0.isSending = false
            $0.error = SchedulingFailure.unavailable.localizedDescription
        }
        // A new command cannot overwrite the unknown operation.
        await store.send(.send(.settings(false)))
        await store.send(.retry) {
            $0.revision = 2
            $0.isSending = true
            $0.error = nil
        }
        await store.receive(\.mutationCompleted) {
            $0.snapshot = saved
            $0.isSending = false
            $0.pendingCommand = nil
            $0.operationID = nil
        }
        #expect(await recorder.ids == [id, id])
        #expect(await recorder.commands == [.settings(true), .settings(true)])
    }

    @Test("通報番号は成功した操作IDだけを表示し、結果不明時は成功表示しない")
    func reportReceiptAppearsOnlyAfterAcknowledgement() async {
        let operationID = UUID(uuidString: "00000000-0000-4000-8000-000000000017")!
        let command = SchedulingCommand.report(UUID(), .spam)
        let recorder = SchedulingOperationRecorder()
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"
        state.snapshot = .empty
        state.reportReceipt = UUID()
        state.message = "前回の通報を受け付けました。"
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.automaticSchedulingEffects.execute = { command, id, _ in
                if await recorder.record(command, id) == 1 { throw SchedulingFailure.unavailable }
                return .empty
            }
        }
        await store.send(.send(command)) {
            $0.revision = 1
            $0.isSending = true
            $0.pendingCommand = command
            $0.operationID = operationID
            $0.message = nil
            $0.reportReceipt = nil
        }
        await store.receive(\.failed) {
            $0.isSending = false
            $0.error = SchedulingFailure.unavailable.localizedDescription
        }
        #expect(store.state.reportReceipt == nil)
        await store.send(.retry) {
            $0.revision = 2
            $0.isSending = true
            $0.error = nil
        }
        await store.receive(\.mutationCompleted) {
            $0.isSending = false
            $0.pendingCommand = nil
            $0.operationID = nil
            $0.reportReceipt = operationID
            $0.message = "通報を受け付けました。"
        }
        #expect(await recorder.ids == [operationID, operationID])
    }

    @Test("送信中は別の変更要求を送らない")
    func duplicateMutationIsBlocked() async {
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"
        state.snapshot = .empty
        state.isSending = true
        state.pendingCommand = .settings(true)
        let id = UUID()
        state.operationID = id
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() }
        await store.send(.send(.settings(false)))
        #expect(store.state.operationID == id)
        #expect(store.state.pendingCommand == .settings(true))
    }

    @Test("旧sessionと旧revisionの提案を表示しない")
    func staleSnapshotRejected() async {
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "new"
        state.revision = 4
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() }
        var snapshot = SchedulingSnapshot.empty
        snapshot.enabled = true
        await store.send(.loaded(snapshot, owner: "old", revision: 4))
        await store.send(.loaded(snapshot, owner: "new", revision: 3))
        #expect(store.state.snapshot == nil)
    }

    @Test("セッション破棄で匿名提案も再送内容も消去する")
    func resetClearsSensitiveState() async {
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"
        state.snapshot = .empty
        state.operationID = UUID()
        state.pendingCommand = .settings(true)
        state.shareAcceptance[UUID()] = true
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() }
        await store.send(.reset) { $0 = .init(); $0.revision = 1 }
    }

    @Test("Push拒否でも受信箱と回答を利用できる")
    func notificationsAreOptional() async {
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"; state.snapshot = .empty
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() } withDependencies: {
            $0.automaticSchedulingEffects.requestNotifications = { _ in false }
        }
        await store.send(.requestNotifications) { $0.isRegisteringNotifications = true }
        await store.receive(\.notificationsCompleted) {
            $0.isRegisteringNotifications = false
            $0.notificationMessage = "通知は許可されていません。受信箱から利用できます。"
        }
        #expect(store.state.canMutate)
    }

    @Test("認証失効では提案を破棄して親へログインを要求する")
    func unauthorizedClearsProposal() async {
        var state = AutomaticSchedulingFeature.State()
        state.ownerID = "owner"
        state.snapshot = .init(enabled: true, permissions: [], proposals: [schedulingProposal()], notifications: [])
        state.revision = 2
        let store = TestStore(initialState: state) { AutomaticSchedulingFeature() }
        await store.send(.failed(.unauthorized, owner: "owner", revision: 2, mutation: false)) {
            $0.snapshot = nil
            $0.error = SchedulingFailure.unauthorized.localizedDescription
        }
        await store.receive(\.delegate)
    }

    @Test("通知停止の通信失敗でもログアウトできる")
    func logoutDoesNotDependOnDeviceNetwork() async {
        let signedOut = LockIsolated(false)
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = .init(userID: "owner", accessToken: "token")
        state.snapshot = .empty()
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.authenticationClient.signOut = { signedOut.setValue(true) }
            $0.automaticSchedulingEffects.disableDevice = { _ in throw SchedulingFailure.unavailable }
        }
        await store.send(.logoutTapped) { $0.isLoading = true }
        await store.receive(\.logoutCompleted) {
            $0 = .init()
            $0.automaticScheduling.revision = 1
            $0.route = .onboarding
        }
        await store.receive(\.operationFailed) {
            $0.alertMessage = "ログアウトしました。端末の通知停止は確認できませんでした。通知本文に相手名や暇時間は含まれません。"
        }
        #expect(signedOut.value)
    }

    @Test("本番Homeは自動確定した予定を投影する")
    func confirmedProjection() {
        let proposal = schedulingProposal(status: .confirmed, response: .accepted)
        var snapshot = SchedulingSnapshot.empty
        snapshot.proposals = [proposal]
        let items = HomeView.scheduleItems(.empty(), scheduling: snapshot)
        #expect(items.count == 1)
        #expect(items.first?.id == .plan(proposal.id))
        #expect(items.first?.kind == .plan)
    }

    @Test("開発とTestFlightのAPNs環境はビルド構成から変換する")
    func pushEnvironment() throws {
        #expect(try SchedulingPushEnvironment.apiValue("development") == "sandbox")
        #expect(try SchedulingPushEnvironment.apiValue("production") == "production")
        #expect(throws: SchedulingFailure.rejected) { try SchedulingPushEnvironment.apiValue(nil) }
    }
}

@Suite("Automatic scheduling HTTP", .serialized)
struct AutomaticSchedulingAdapterTests {
    @Test("匿名提案を読み込み、回答全体・OK共有false・operationID・本人versionを送る")
    func responseContract() async throws {
        let recorded = SchedulingRequestRecorder()
        let proposal = schedulingProposal()
        let snapshot = SchedulingSnapshot(enabled: true, permissions: [], proposals: [proposal], notifications: [])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(snapshot)
        let repository = BackendAutomaticSchedulingAdapter(baseURL: URL(string: "https://api.example.com/")!, session: schedulingSession { request in
            recorded.append(request)
            return (200, body)
        }).repository()
        let value = try await repository.load("token")
        #expect(value.proposals.first?.peer == nil)
        let operationID = UUID()
        _ = try await repository.execute(.response(proposal.id, .accepted, shareAcceptance: false, version: 1), operationID, "token")
        let request = try #require(recorded.requests.last)
        #expect(request.url?.path == "/v1/automatic-scheduling/proposals/\(proposal.id.uuidString)/response")
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let requestBody = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(json["operationId"] as? String == operationID.uuidString)
        #expect(json["shareAcceptance"] as? Bool == false)
        #expect(json["expectedVersion"] as? Int == 1)
        #expect(json["response"] as? String == "accepted")
        #expect(json["intervals"] == nil)
    }

    @Test("許可されない匿名投影の相手識別をfail closedにする")
    func invalidIdentityProjection() async throws {
        let proposal = schedulingProposal(peer: .init(userId: UUID(), nickname: "非公開", presetIconKey: "sun.max.fill"))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(SchedulingSnapshot(enabled: true, permissions: [], proposals: [proposal], notifications: []))
        let repository = BackendAutomaticSchedulingAdapter(baseURL: URL(string: "https://example.com/")!, session: schedulingSession { _ in (200, data) }).repository()
        await #expect(throws: SchedulingFailure.invalidResponse) { try await repository.load("token") }
    }

    @Test("認証・競合・結果不明は安全なエラーへ変換しレスポンス本文を表示しない")
    func safeErrors() async {
        for (status, expected) in [(401, SchedulingFailure.unauthorized), (409, .conflict), (503, .unavailable)] {
            let repository = BackendAutomaticSchedulingAdapter(baseURL: URL(string: "https://example.com/")!, session: schedulingSession { _ in
                (status, Data("private datetime token".utf8))
            }).repository()
            await #expect(throws: expected) { try await repository.load("token") }
        }
    }

    @Test("片側OKの撤回は本人version付きcancelで送り、二度目の回答を送らない")
    func acceptedResponseWithdrawalUsesCancel() async throws {
        let recorder = SchedulingRequestRecorder()
        let repository = BackendAutomaticSchedulingAdapter(baseURL: URL(string: "https://example.com/")!, session: schedulingSession { request in
            recorder.append(request)
            return (200, Data(#"{"enabled":false,"permissions":[],"proposals":[],"notifications":[]}"#.utf8))
        }).repository()
        #expect(schedulingProposal().withdrawalCommand == nil)
        let proposal = schedulingProposal(status: .pending, response: .accepted, version: 2)
        let command = try #require(proposal.withdrawalCommand)
        #expect(command == .cancel(proposal.id, version: 2))
        let operationID = UUID()
        _ = try await repository.execute(command, operationID, "token")
        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/automatic-scheduling/proposals/\(proposal.id.uuidString)/cancel")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["expectedVersion"] as? Int == 2)
        #expect(json["operationId"] as? String == operationID.uuidString)
        #expect(json["response"] == nil)
    }

    @Test("匿名提案の通報とブロックは相手IDをクライアントに要求しない")
    func anonymousSafetyContract() async throws {
        let recorder = SchedulingRequestRecorder()
        let repository = BackendAutomaticSchedulingAdapter(baseURL: URL(string: "https://example.com/")!, session: schedulingSession { request in
            recorder.append(request)
            return (200, Data(#"{"enabled":false,"permissions":[],"proposals":[],"notifications":[]}"#.utf8))
        }).repository()
        let id = UUID()
        _ = try await repository.execute(.report(id, .harassment), UUID(), "token")
        _ = try await repository.execute(.blockProposal(id), UUID(), "token")
        #expect(recorder.requests.map { $0.url!.path } == ["/v1/automatic-scheduling/proposals/\(id.uuidString)/report", "/v1/automatic-scheduling/proposals/\(id.uuidString)/block"])
    }
}

private func schedulingProposal(status: SchedulingProposal.Status = .pending, response: SchedulingProposal.Response = .pending, peer: SchedulingPeer? = nil, version: Int = 1) -> SchedulingProposal {
    .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, start: Date(timeIntervalSince1970: 2_000_000_000), end: Date(timeIntervalSince1970: 2_000_003_600), status: status, myResponse: response, version: version, shareAcceptance: false, peer: peer, peerResponse: nil, feedback: nil)
}

private actor SchedulingOperationRecorder {
    var ids: [UUID] = []
    var commands: [SchedulingCommand] = []
    func record(_ command: SchedulingCommand, _ id: UUID) -> Int { ids.append(id); commands.append(command); return ids.count }
}

private final class SchedulingRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { values } }
    func append(_ input: URLRequest) {
        var request = input
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            request.httpBody = data
        }
        lock.withLock { values.append(request) }
    }
}

private final class SchedulingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private func schedulingSession(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSession {
    SchedulingURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SchedulingURLProtocol.self]
    return URLSession(configuration: configuration)
}
