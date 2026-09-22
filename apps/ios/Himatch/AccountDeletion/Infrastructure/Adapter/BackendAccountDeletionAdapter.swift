import Foundation

final class BackendAccountDeletionAdapter: @unchecked Sendable {
    private struct RequestPayload: Encodable {
        let appleAuthorizationCode: String
    }

    private struct ResponsePayload: Decodable {
        let reference: String
        let status: AccountDeletionResultStatus
        let statusToken: String?
        let message: String?
    }

    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func client() -> AccountDeletionClient {
        AccountDeletionClient(
            submit: { [self] authorization in
                guard let url = URL(string: "v1/account-deletion-requests", relativeTo: baseURL)?.absoluteURL else {
                    throw BackendClientError.invalidURL
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(authorization.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(authorization.operationID.uuidString, forHTTPHeaderField: "Idempotency-Key")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try encoder.encode(RequestPayload(appleAuthorizationCode: authorization.appleAuthorizationCode))

                let (data, response) = try await session.data(for: request)
                let payload = try decodeResponse(data: data, response: response, acceptedStatusCodes: [200, 202])
                guard let statusToken = payload.statusToken else { throw BackendClientError.invalidResponse }
                return AccountDeletionReceipt(
                    reference: payload.reference,
                    status: payload.status,
                    statusToken: statusToken,
                    message: payload.message
                )
            },
            status: { [self] pending in
                let url = baseURL
                    .appendingPathComponent("v1/account-deletion-requests")
                    .appendingPathComponent(pending.reference)
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Deletion \(pending.statusToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let (data, response) = try await session.data(for: request)
                let payload = try decodeResponse(data: data, response: response, acceptedStatusCodes: [200])
                return AccountDeletionReceipt(
                    reference: payload.reference,
                    status: payload.status,
                    statusToken: pending.statusToken,
                    message: payload.message
                )
            }
        )
    }

    private func decodeResponse(
        data: Data,
        response: URLResponse,
        acceptedStatusCodes: Set<Int>
    ) throws -> ResponsePayload {
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        guard acceptedStatusCodes.contains(http.statusCode) else {
            let message = (try? decoder.decode(BackendErrorPayload.self, from: data))?.message
            throw BackendClientError.response(http.statusCode, message)
        }
        return try decoder.decode(ResponsePayload.self, from: data)
    }
}
