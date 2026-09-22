import Foundation

final class BackendProfileAdapter: @unchecked Sendable {
    private struct ProfilePayload: Codable {
        let nickname: String
        let presetIconKey: String
    }

    private struct ProfileResponse: Decodable {
        let userId: String
        let profile: ProfilePayload?
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func client() -> ProfileClient {
        ProfileClient(
            get: { [self] token in
                let request = try authorizedRequest(path: "v1/me", method: "GET", accessToken: token)
                let (data, response) = try await session.data(for: request)
                let http = try Self.http(response)
                guard http.statusCode == 200 else { throw BackendClientError.response(http.statusCode, Self.message(data)) }
                let payload = try decoder.decode(ProfileResponse.self, from: data)
                return try payload.profile.map { try Self.map(userID: payload.userId, payload: $0) }
            },
            put: { [self] nickname, icon, token in
                var request = try authorizedRequest(path: "v1/me", method: "PUT", accessToken: token)
                request.httpBody = try encoder.encode(ProfilePayload(nickname: nickname, presetIconKey: icon.rawValue))
                let (data, response) = try await session.data(for: request)
                let http = try Self.http(response)
                guard http.statusCode == 200 else { throw BackendClientError.response(http.statusCode, Self.message(data)) }
                let payload = try decoder.decode(ProfileResponse.self, from: data)
                guard let profile = payload.profile else { throw BackendClientError.invalidResponse }
                return try Self.map(userID: payload.userId, payload: profile)
            }
        )
    }

    private func authorizedRequest(path: String, method: String, accessToken: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw BackendClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func map(userID: String, payload: ProfilePayload) throws -> UserProfile {
        UserProfile(
            userID: userID,
            nickname: try ProfilePolicy.validatedNickname(payload.nickname),
            presetIcon: try ProfilePolicy.presetIcon(payload.presetIconKey)
        )
    }

    private static func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        return response
    }

    private static func message(_ data: Data) -> String? {
        (try? JSONDecoder().decode(BackendErrorPayload.self, from: data))?.message
    }
}

struct BackendErrorPayload: Decodable {
    struct ErrorDetail: Decodable {
        let code: String
        let message: String
        let fields: [String: String]?
    }

    let error: ErrorDetail

    var message: String {
        error.fields?["nickname"]
            ?? error.fields?["presetIconKey"]
            ?? error.message
    }
}

enum BackendClientError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case response(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL, .invalidResponse:
            "サーバーから正しい応答を取得できませんでした。"
        case let .response(_, message):
            message ?? "サーバーで処理を完了できませんでした。"
        }
    }
}
