import Foundation
import Testing
@testable import Himatch

@Suite("Backend adapters", .serialized)
struct BackendAdapterTests {
    @Test("Profile adapter maps GET and PUT contracts")
    func profileContract() async throws {
        let recorder = RequestRecorder()
        let session = stubSession { request in
            recorder.append(request)
            let body: String
            if request.httpMethod == "GET" {
                body = #"{"userId":"00000000-0000-0000-0000-000000000001","profile":null}"#
            } else {
                body = #"{"userId":"00000000-0000-0000-0000-000000000001","profile":{"nickname":"ひまり","presetIconKey":"sun.max.fill"}}"#
            }
            return (200, Data(body.utf8))
        }
        let client = BackendProfileAdapter(baseURL: URL(string: "https://api.example.com/")!, session: session).client()

        #expect(try await client.get("access") == nil)
        let profile = try await client.put("ひまり", .sun, "access")

        #expect(profile.nickname == "ひまり")
        #expect(profile.presetIcon == .sun)
        #expect(recorder.requests.map(\.httpMethod) == ["GET", "PUT"])
        #expect(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access" })
    }

    @Test("募集カテゴリが本人暇の明示未選択を上書きしない")
    func explicitUnselectedAvailabilityMetadata() async throws {
        let recorder = RequestRecorder()
        let session = stubSession { request in
            recorder.append(request)
            return (200, Data(#"{"hosting":{"id":"00000000-0000-4000-8000-000000000010","start":"2026-10-05T01:00:00.000Z","end":"2026-10-05T02:00:00.000Z","mode":"online","category":"game","status":"open","version":1,"acceptedParticipants":[]}}"#.utf8))
        }
        let adapter = BackendHostingAdapter(baseURL: URL(string: "https://api.example.com/")!, session: session)
        let draft = HostingDraft(mode: .online, category: .game, start: Date(timeIntervalSince1970: 2_000_000_000), duration: 3600,
                                 friends: [FriendProfile(id: UUID(), displayName: "りく", icon: "sun.max.fill")],
                                 availabilityMetadata: .init(category: nil, visibility: .privateUntilAccepted))
        _ = try await adapter.create(draft, operationID: draft.operationID, accessToken: "token")
        let body = try #require(recorder.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let metadata = try #require(json["availabilityMetadata"] as? [String: Any])
        #expect(json["category"] as? String == "game")
        #expect(metadata["category"] == nil || metadata["category"] is NSNull)
        #expect(metadata["visibility"] as? String == "privateUntilAccepted")
    }

    @Test("Deletion adapter sends UTF-8 Apple code and idempotency key")
    func deletionContract() async throws {
        let recorder = RequestRecorder()
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let session = stubSession { request in
            recorder.append(request)
            return (
                202,
                Data(#"{"reference":"DEL-42","status":"actionRequired","statusToken":"status-token","message":"再試行してください"}"#.utf8)
            )
        }
        let client = BackendAccountDeletionAdapter(baseURL: URL(string: "https://api.example.com/")!, session: session).client()

        let receipt = try await client.submit(
            AccountDeletionAuthorization(
                appleAuthorizationCode: "apple-code.value",
                operationID: operationID,
                accessToken: "access"
            )
        )

        let request = try #require(recorder.requests.first)
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == operationID.uuidString)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
        #expect(String(data: try #require(request.httpBody), encoding: .utf8)?.contains("apple-code.value") == true)
        #expect(receipt.status == .actionRequired)
        #expect(receipt.statusToken == "status-token")
    }

    @Test("Friendship adapter loads issued code and sends versioned operations")
    func friendshipContract() async throws {
        let recorder = RequestRecorder()
        let snapshot = #"{"inviteCode":{"value":"HIMA-ABCD-EFGH-JKMP-QRST","expiresAt":"2026-09-30T00:00:00.000Z"},"friends":[{"profile":{"userId":"00000000-0000-4000-8000-000000000002","nickname":"りく","presetIconKey":"figure.run"},"version":3,"createdAt":"2026-09-23T00:00:00.000Z"}],"incomingRequests":[],"outgoingRequests":[]}"#
        let candidate = #"{"candidate":{"userId":"00000000-0000-4000-8000-000000000002","nickname":"りく","presetIconKey":"figure.run"}}"#
        let session = stubSession { request in
            recorder.append(request)
            return request.url?.path.hasSuffix("/resolve") == true
                ? (200, Data(candidate.utf8))
                : (200, Data(snapshot.utf8))
        }
        let client = BackendFriendshipAdapter(
            baseURL: URL(string: "https://api-staging.example.com/")!,
            session: session
        ).client()

        let loaded = try await client.load("access")
        let resolved = try await client.resolveCode("HIMA-ABCD-EFGH-JKMP-QRST", "access")
        _ = try await client.removeFriend(
            UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            3,
            UUID(uuidString: "00000000-0000-4000-8000-000000000099")!,
            "access"
        )

        #expect(loaded.inviteCode?.value == "HIMA-ABCD-EFGH-JKMP-QRST")
        #expect(loaded.friends.first?.relationshipVersion == 3)
        #expect(resolved.displayName == "りく")
        #expect(recorder.requests.map { $0.url?.path } == [
            "/v1/friendships",
            "/v1/friendship-invite-code/resolve",
            "/v1/friendships/00000000-0000-4000-8000-000000000002",
        ])
        #expect(recorder.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer access"
        })
        let body = try #require(recorder.requests.last?.httpBody)
        #expect(String(data: body, encoding: .utf8)?.contains(#""expectedVersion":3"#) == true)
    }

    @Test("Availability adapter uses owner slots contract")
    func availabilityContract() async throws {
        let recorder = RequestRecorder()
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        let slot = #"{"id":"00000000-0000-4000-8000-000000000010","start":"2026-09-26T01:00:00.000Z","end":"2026-09-26T03:00:00.000Z","category":"game","visibility":"privateUntilAccepted"}"#
        let session = stubSession { request in
            recorder.append(request)
            if request.httpMethod == "GET" { return (200, Data(("{\"slots\":[" + slot + "]}").utf8)) }
            if request.httpMethod == "DELETE" { return (204, Data()) }
            return (200, Data(("{\"slots\":[" + slot + "]}").utf8))
        }
        let client = BackendAvailabilityAdapter(
            baseURL: URL(string: "https://api.example.com/")!,
            session: session
        )
        let model = AvailabilitySlot(
            id: id,
            interval: TimeIntervalRange(
                id: id,
                start: Date(timeIntervalSince1970: 1_790_380_800),
                end: Date(timeIntervalSince1970: 1_790_388_000)
            ),
            category: .game
        )

        #expect(try await client.load(accessToken: "access").first?.id == id)
        #expect(try await client.put(model, accessToken: "access").first?.category == .game)
        #expect(try await client.delete(id: id, accessToken: "access").first?.id == id)
        #expect(recorder.requests.map(\.httpMethod) == ["GET", "POST", "DELETE", "GET"])
        #expect(recorder.requests[1].url?.path == "/v1/availability/intervals:union")
        #expect(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access" })
        let body = try #require(recorder.requests[1].httpBody)
        #expect(String(data: body, encoding: .utf8)?.contains(#""start":"#) == true)
        #expect(String(data: body, encoding: .utf8)?.contains(#""category":"game"#) == true)
        #expect(String(data: body, encoding: .utf8)?.contains(#""operationId":"00000000-0000-4000-8000-000000000010"#) == true)
    }

    @Test("Hosting adapter sends typed friend target and decodes host/invitee projections")
    func hostingContract() async throws {
        let recorder = RequestRecorder()
        let hostingID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        let friendID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
        let operationID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
        let responseOperationID = UUID(uuidString: "00000000-0000-4000-8000-000000000104")!
        let cancelOperationID = UUID(uuidString: "00000000-0000-4000-8000-000000000106")!
        let hostResponse = #"{"hosting":{"id":"00000000-0000-4000-8000-000000000101","start":"2026-09-28T01:00:00.000Z","end":"2026-09-28T03:00:00.000Z","mode":"offline","area":"shibuya","category":"game","status":"open","version":1,"acceptedParticipants":[]}}"#
        let cancelledResponse = hostResponse
            .replacingOccurrences(of: "\"status\":\"open\"", with: "\"status\":\"cancelled\"")
            .replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        let inviteeResponse = #"{"hosting":{"id":"00000000-0000-4000-8000-000000000101","start":"2026-09-28T01:00:00.000Z","end":"2026-09-28T03:00:00.000Z","mode":"offline","area":"shibuya","category":"game","status":"open","version":2,"host":{"userId":"00000000-0000-4000-8000-000000000105","nickname":"さき","presetIconKey":"figure.run"},"myInvitation":{"status":"accepted","version":2,"intervals":[{"start":"2026-09-28T01:30:00.000Z","end":"2026-09-28T02:00:00.000Z"}]}}}"#
        let session = stubSession { request in
            recorder.append(request)
            let response: String
            if request.url?.path.hasSuffix("/response") == true { response = inviteeResponse }
            else if request.url?.path.hasSuffix("/cancel") == true { response = cancelledResponse }
            else { response = hostResponse }
            return (200, Data(response.utf8))
        }
        let adapter = BackendHostingAdapter(baseURL: URL(string: "https://api.example.com/")!, session: session)
        let friend = FriendProfile(id: friendID, displayName: "ゆう", icon: "figure.run")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let start = formatter.date(from: "2026-09-28T01:00:00.000Z")!
        let draft = HostingDraft(
            mode: .offline,
            area: .shibuya,
            category: .game,
            start: start,
            duration: 7_200,
            friends: [friend],
            availabilityCategory: .meal,
            availabilityVisibility: .shareOnHosting
        )

        let created = try await adapter.create(draft, operationID: operationID, accessToken: "access")
        #expect(created.id == hostingID)
        #expect(created.status == .recruiting)
        let createRequest = try #require(recorder.requests.first)
        #expect(createRequest.httpMethod == "POST")
        #expect(createRequest.url?.path == "/v1/hostings")
        #expect(createRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access")
        let createBody = try #require(createRequest.httpBody)
        let createJSON = try #require(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        #expect(createJSON["mode"] as? String == "offline")
        #expect(createJSON["area"] as? String == "shibuya")
        #expect(createJSON["operationId"] as? String == operationID.uuidString)
        let targets = try #require(createJSON["targets"] as? [[String: String]])
        #expect(targets == [["type": "friend", "id": friendID.uuidString]])
        let metadata = try #require(createJSON["availabilityMetadata"] as? [String: String])
        #expect(metadata["category"] == "meal")
        #expect(metadata["visibility"] == "shareOnHosting")

        let partial = TimeIntervalRange(
            start: formatter.date(from: "2026-09-28T01:30:00.000Z")!,
            end: formatter.date(from: "2026-09-28T02:00:00.000Z")!
        )
        let answered = try await adapter.respond(
            id: hostingID,
            status: .accepted,
            intervals: [partial],
            operationID: responseOperationID,
            expectedVersion: 1,
            accessToken: "access"
        )
        #expect(answered.isHostedByMe == false)
        #expect(answered.host?.displayName == "さき")
        #expect(answered.myInvitation?.status == .accepted)
        let mappedPartial = try #require(answered.myInvitation?.intervals?.first)
        #expect(mappedPartial.start == partial.start)
        #expect(mappedPartial.end == partial.end)
        let responseRequest = try #require(recorder.requests.last)
        #expect(responseRequest.httpMethod == "PUT")
        #expect(responseRequest.url?.path == "/v1/hostings/\(hostingID.uuidString)/response")
        let responseBody = try #require(JSONSerialization.jsonObject(with: responseRequest.httpBody!) as? [String: Any])
        #expect(responseBody["status"] as? String == "accepted")
        #expect(responseBody["expectedVersion"] as? Int == 1)
        #expect(responseBody["operationId"] as? String == responseOperationID.uuidString)
        #expect((responseBody["intervals"] as? [[String: String]])?.count == 1)

        let cancelled = try await adapter.cancel(
            id: hostingID,
            operationID: cancelOperationID,
            expectedVersion: 1,
            accessToken: "access"
        )
        #expect(cancelled.status == .cancelled)
        let cancelRequest = try #require(recorder.requests.last)
        #expect(cancelRequest.httpMethod == "POST")
        #expect(cancelRequest.url?.path == "/v1/hostings/\(hostingID.uuidString)/cancel")
        let cancelBody = try #require(JSONSerialization.jsonObject(with: cancelRequest.httpBody!) as? [String: Any])
        #expect(cancelBody["expectedVersion"] as? Int == 1)
        #expect(cancelBody["operationId"] as? String == cancelOperationID.uuidString)
    }

    @Test("Deletion adapter restores pending status with deletion authorization")
    func deletionStatusContract() async throws {
        let recorder = RequestRecorder()
        let session = stubSession { request in
            recorder.append(request)
            return (
                200,
                Data(#"{"reference":"DEL-42","status":"completed","message":"削除が完了しました"}"#.utf8)
            )
        }
        let client = BackendAccountDeletionAdapter(
            baseURL: URL(string: "https://api.example.com/")!,
            session: session
        ).client()

        let receipt = try await client.status(PendingAccountDeletion(
            reference: "DEL-42",
            statusToken: "status-token"
        ))

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/account-deletion-requests/DEL-42")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Deletion status-token")
        #expect(receipt.status == .completed)
        #expect(receipt.statusToken == "status-token")
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { storage } }
    func append(_ request: URLRequest) {
        var recorded = request
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            recorded.httpBody = data
        }
        lock.withLock { storage.append(recorded) }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func stubSession(
    handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)
) -> URLSession {
    StubURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}
