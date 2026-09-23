import Foundation

final class BackendFriendshipAdapter: @unchecked Sendable {
    private struct ProfilePayload: Decodable {
        let userId: UUID
        let nickname: String
        let presetIconKey: String
    }

    private struct InviteCodePayload: Decodable {
        let value: String
        let expiresAt: String
    }

    private struct FriendshipPayload: Decodable {
        let profile: ProfilePayload
        let version: Int
    }

    private struct RequestPayload: Decodable {
        let id: UUID
        let profile: ProfilePayload
        let version: Int
    }

    private struct SnapshotPayload: Decodable {
        let inviteCode: InviteCodePayload?
        let friends: [FriendshipPayload]
        let incomingRequests: [RequestPayload]
        let outgoingRequests: [RequestPayload]
    }

    private struct CandidatePayload: Decodable {
        let candidate: ProfilePayload
    }

    private struct CodeInput: Encodable {
        let code: String
    }

    private struct SendRequestInput: Encodable {
        let code: String
        let operationId: UUID
    }

    private struct MutationInput: Encodable {
        let operationId: UUID
        let expectedVersion: Int
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func client() -> FriendshipClient {
        FriendshipClient(
            load: { [self] token in
                try await snapshot(path: "v1/friendships", method: "GET", accessToken: token)
            },
            rotateCode: { [self] token in
                try await snapshot(path: "v1/friendship-invite-code/rotate", method: "POST", accessToken: token)
            },
            resolveCode: { [self] code, token in
                let data = try await request(
                    path: "v1/friendship-invite-code/resolve",
                    method: "POST",
                    body: CodeInput(code: code),
                    accessToken: token
                )
                return Self.profile(try decoder.decode(CandidatePayload.self, from: data).candidate)
            },
            sendRequest: { [self] code, operationID, token in
                try await snapshot(
                    path: "v1/friendship-requests",
                    method: "POST",
                    body: SendRequestInput(code: code, operationId: operationID),
                    accessToken: token
                )
            },
            transitionRequest: { [self] requestID, transition, version, operationID, token in
                try await snapshot(
                    path: "v1/friendship-requests/\(requestID.uuidString)/\(transition.rawValue)",
                    method: "POST",
                    body: MutationInput(operationId: operationID, expectedVersion: version),
                    accessToken: token
                )
            },
            removeFriend: { [self] friendID, version, operationID, token in
                try await snapshot(
                    path: "v1/friendships/\(friendID.uuidString)",
                    method: "DELETE",
                    body: MutationInput(operationId: operationID, expectedVersion: version),
                    accessToken: token
                )
            }
        )
    }

    private func snapshot(
        path: String,
        method: String,
        accessToken: String
    ) async throws -> FriendshipSnapshot {
        try Self.snapshot(decoder.decode(
            SnapshotPayload.self,
            from: try await request(path: path, method: method, accessToken: accessToken)
        ))
    }

    private func snapshot<Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        accessToken: String
    ) async throws -> FriendshipSnapshot {
        try Self.snapshot(decoder.decode(
            SnapshotPayload.self,
            from: try await request(path: path, method: method, body: body, accessToken: accessToken)
        ))
    }

    private func request(
        path: String,
        method: String,
        accessToken: String
    ) async throws -> Data {
        let request = try authorizedRequest(path: path, method: method, accessToken: accessToken)
        return try await responseData(for: request)
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        accessToken: String
    ) async throws -> Data {
        var request = try authorizedRequest(path: path, method: method, accessToken: accessToken)
        request.httpBody = try encoder.encode(body)
        return try await responseData(for: request)
    }

    private func authorizedRequest(path: String, method: String, accessToken: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw BackendClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendClientError.response(http.statusCode, Self.message(data))
        }
        return data
    }

    private static func snapshot(_ payload: SnapshotPayload) throws -> FriendshipSnapshot {
        let inviteCode: InviteCode?
        if let payload = payload.inviteCode {
            guard let expiresAt = date(payload.expiresAt) else {
                throw BackendClientError.invalidResponse
            }
            inviteCode = InviteCode(value: payload.value, expiresAt: expiresAt)
        } else {
            inviteCode = nil
        }
        return FriendshipSnapshot(
            inviteCode: inviteCode,
            friends: payload.friends.map {
                var friend = profile($0.profile)
                friend.relationshipVersion = $0.version
                return friend
            },
            requests: payload.incomingRequests.map {
                FriendRequest(id: $0.id, person: profile($0.profile), direction: .incoming, version: $0.version)
            } + payload.outgoingRequests.map {
                FriendRequest(id: $0.id, person: profile($0.profile), direction: .outgoing, version: $0.version)
            }
        )
    }

    private static func profile(_ payload: ProfilePayload) -> FriendProfile {
        FriendProfile(id: payload.userId, displayName: payload.nickname, icon: payload.presetIconKey)
    }

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func message(_ data: Data) -> String? {
        (try? JSONDecoder().decode(BackendErrorPayload.self, from: data))?.message
    }
}
