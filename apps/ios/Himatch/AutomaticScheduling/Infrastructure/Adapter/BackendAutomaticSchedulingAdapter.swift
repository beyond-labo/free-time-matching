import Foundation

final class BackendAutomaticSchedulingAdapter: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func repository() -> AutomaticSchedulingRepository {
        .init(
            load: { [self] token in try await request(path: "", method: "GET", body: nil, token: token) },
            execute: { [self] command, operationID, token in
                let mutation = Self.mutation(command, operationID: operationID)
                return try await request(path: mutation.path, method: mutation.method, body: mutation.body, token: token)
            },
            registerDevice: { [self] deviceToken, environment, enabled, token in
                try await request(path: "/device", method: "PUT", body: ["token": deviceToken, "environment": environment, "enabled": enabled], token: token)
            }
        )
    }

    private static func mutation(_ command: SchedulingCommand, operationID: UUID) -> (path: String, method: String, body: [String: Any]) {
        var body: [String: Any] = ["operationId": operationID.uuidString]
        switch command {
        case let .settings(enabled):
            body["enabled"] = enabled
            return ("/settings", "PUT", body)
        case let .permission(id, enabled):
            body["enabled"] = enabled
            return ("/permissions/\(id.uuidString)", "PUT", body)
        case let .response(id, response, shareAcceptance, version):
            body["response"] = response.rawValue
            body["shareAcceptance"] = shareAcceptance
            body["expectedVersion"] = version
            return ("/proposals/\(id.uuidString)/response", "PUT", body)
        case let .cancel(id, version):
            body["expectedVersion"] = version
            return ("/proposals/\(id.uuidString)/cancel", "POST", body)
        case let .feedback(id, feedback):
            body["played"] = feedback.played
            body["bothersome"] = feedback.bothersome
            body["privacyConcern"] = feedback.privacyConcern
            return ("/proposals/\(id.uuidString)/feedback", "PUT", body)
        case let .blockFriend(id): return ("/blocks/\(id.uuidString)", "POST", body)
        case let .blockProposal(id): return ("/proposals/\(id.uuidString)/block", "POST", body)
        case let .report(id, reason):
            body["reason"] = reason.rawValue
            return ("/proposals/\(id.uuidString)/report", "POST", body)
        case let .reportFriend(id, reason):
            body["reason"] = reason.rawValue
            return ("/reports/\(id.uuidString)", "POST", body)
        }
    }

    private func request(path: String, method: String, body: [String: Any]?, token: String) async throws -> SchedulingSnapshot {
        let url = baseURL.appendingPathComponent("v1/automatic-scheduling" + path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SchedulingFailure.unavailable }
        guard let http = response as? HTTPURLResponse else { throw SchedulingFailure.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw SchedulingFailure.unauthorized
        case 409: throw SchedulingFailure.conflict
        case 400, 403, 404: throw SchedulingFailure.rejected
        default: throw SchedulingFailure.unavailable
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let value = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: value) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                guard let date = formatter.date(from: value) else { throw SchedulingFailure.invalidResponse }
                return date
            }
            let value = try decoder.decode(SchedulingSnapshot.self, from: data)
            for proposal in value.proposals {
                guard proposal.end > proposal.start, proposal.version > 0 else { throw SchedulingFailure.invalidResponse }
                // Never render identity from an invalid anonymous projection.
                guard proposal.peer == nil || proposal.status == .confirmed || proposal.peerResponse == .accepted else {
                    throw SchedulingFailure.invalidResponse
                }
                guard proposal.peerResponse == nil || proposal.peerResponse == .accepted else { throw SchedulingFailure.invalidResponse }
            }
            return value
        } catch { throw SchedulingFailure.invalidResponse }
    }
}
