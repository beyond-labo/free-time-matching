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
