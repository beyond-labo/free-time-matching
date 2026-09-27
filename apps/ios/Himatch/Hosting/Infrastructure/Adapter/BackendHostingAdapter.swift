import Foundation
import OSLog

/// Authenticated client for the audience-projected hosting and invitation API.
final class BackendHostingAdapter: @unchecked Sendable {
    struct CreateInput: Encodable {
        struct Target: Encodable { let type = "friend"; let id: UUID }
        let start: Date
        let end: Date
        let mode: String
        let area: String?
        let category: String?
        let targets: [Target]
        let availabilityMetadata: AvailabilityMetadata
        let operationId: UUID
    }
    struct AvailabilityMetadata: Encodable { let category: String?; let visibility: String }
    struct ResponseInput: Encodable {
        struct Interval: Encodable { let start: Date; let end: Date }
        let status: String
        let intervals: [Interval]
        let operationId: UUID
        let expectedVersion: Int
    }

    private struct IntervalPayload: Decodable { let start: Date; let end: Date }
    private struct ParticipantPayload: Decodable {
        let userId: UUID; let nickname: String; let presetIconKey: String; let intervals: [IntervalPayload]
    }
    private struct InvitationPayload: Decodable {
        let status: HostingInvitation.Status; let version: Int; let intervals: [IntervalPayload]?
    }
    private struct HostingPayload: Decodable {
        let id: UUID; let start: Date; let end: Date; let mode: String; let area: String?; let category: String?
        let status: String; let version: Int; let acceptedParticipants: [ParticipantPayload]?; let myInvitation: InvitationPayload?
        let host: HostPayload?
    }
    private struct HostPayload: Decodable { let userId: UUID; let nickname: String; let presetIconKey: String }
    private struct HostingResponse: Decodable { let hosting: HostingPayload }
    private struct HostingCollection: Decodable { let hostings: [HostingPayload] }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "Himatch", category: "Hosting")

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func load(accessToken: String) async throws -> (hostings: [Hosting], invitations: [Hosting]) {
        let data = try await request(path: "v1/hostings", method: "GET", accessToken: accessToken)
        let values = try decoder.decode(HostingCollection.self, from: data).hostings.map(Self.map)
        return (values.filter(\.isHostedByMe), values.filter { !$0.isHostedByMe })
    }

    func create(_ draft: HostingDraft, operationID: UUID, accessToken: String) async throws -> Hosting {
        var request = try authorizedRequest(path: "v1/hostings", method: "POST", accessToken: accessToken)
        request.httpBody = try encoder.encode(CreateInput(
            start: draft.start,
            end: draft.start.addingTimeInterval(draft.duration),
            mode: Self.modeValue(draft.mode),
            area: draft.mode == .offline ? Self.areaValue(draft.area) : nil,
            category: Self.categoryValue(draft.category),
            targets: draft.friends.map { .init(id: $0.id) },
            availabilityMetadata: .init(
                category: Self.categoryValue(draft.availabilityCategory ?? draft.category),
                visibility: (draft.availabilityVisibility ?? .privateUntilAccepted).rawValue
            ),
            operationId: operationID
        ))
        let data = try await responseData(for: request)
        return try Self.map(decoder.decode(HostingResponse.self, from: data).hosting)
    }

    func respond(id: UUID, status: HostingInvitation.Status, intervals: [TimeIntervalRange], operationID: UUID,
                 expectedVersion: Int, accessToken: String) async throws -> Hosting {
        var request = try authorizedRequest(path: "v1/hostings/\(id.uuidString)/response", method: "PUT", accessToken: accessToken)
        request.httpBody = try encoder.encode(ResponseInput(
            status: status.rawValue,
            intervals: intervals.map { .init(start: $0.start, end: $0.end) },
            operationId: operationID,
            expectedVersion: expectedVersion
        ))
        let data = try await responseData(for: request)
        return try Self.map(decoder.decode(HostingResponse.self, from: data).hosting)
    }

    func cancel(id: UUID, operationID: UUID, expectedVersion: Int, accessToken: String) async throws -> Hosting {
        struct Input: Encodable { let operationId: UUID; let expectedVersion: Int }
        var request = try authorizedRequest(path: "v1/hostings/\(id.uuidString)/cancel", method: "POST", accessToken: accessToken)
        request.httpBody = try encoder.encode(Input(operationId: operationID, expectedVersion: expectedVersion))
        let data = try await responseData(for: request)
        return try Self.map(decoder.decode(HostingResponse.self, from: data).hosting)
    }

    private func request(path: String, method: String, accessToken: String) async throws -> Data {
        try await responseData(for: authorizedRequest(path: path, method: method, accessToken: accessToken))
    }
    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        if let requestID = http.value(forHTTPHeaderField: "X-Request-ID") {
            logger.info("Hosting request \(requestID, privacy: .public) completed with status \(http.statusCode)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendClientError.response(http.statusCode, (try? JSONDecoder().decode(BackendErrorPayload.self, from: data))?.message)
        }
        return data
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
    private static func map(_ value: HostingPayload) throws -> Hosting {
        let status: HostingStatus
        switch value.status {
        case "open": status = .recruiting
        case "cancelled": status = .cancelled
        case "expired": status = .expired
        default: throw BackendClientError.invalidResponse
        }
        let mode: HostingMode
        switch value.mode {
        case "online": mode = .online
        case "offline": mode = .offline
        default: throw BackendClientError.invalidResponse
        }
        let participants = (value.acceptedParticipants ?? []).map { participant in
            Participation(
                id: participant.userId,
                friend: FriendProfile(id: participant.userId, displayName: participant.nickname, icon: participant.presetIconKey),
                approvedIntervals: participant.intervals.map { TimeIntervalRange(start: $0.start, end: $0.end) }
            )
        }
        let invitation = value.myInvitation.map {
            HostingInvitation(status: $0.status, version: $0.version,
                              intervals: $0.intervals?.map { TimeIntervalRange(start: $0.start, end: $0.end) })
        }
        return Hosting(
            id: value.id, mode: mode, area: area(value.area), category: value.category.flatMap(category),
            candidateRange: TimeIntervalRange(id: value.id, start: value.start, end: value.end),
            requiredDuration: value.end.timeIntervalSince(value.start), friends: [], participants: participants,
            status: status, version: value.version, myInvitation: invitation, isHostedByMe: invitation == nil,
            host: value.host.map { FriendProfile(id: $0.userId, displayName: $0.nickname, icon: $0.presetIconKey) }
        )
    }
    private static func modeValue(_ value: HostingMode) -> String { value == .online ? "online" : "offline" }
    private static func areaValue(_ value: HostingArea?) -> String? {
        switch value { case .shinjuku: "shinjuku"; case .shibuya: "shibuya"; case .discussLater: "discussLater"; case nil: nil }
    }
    private static func area(_ value: String?) -> HostingArea? {
        switch value { case "shinjuku": .shinjuku; case "shibuya": .shibuya; case "discussLater": .discussLater; default: nil }
    }
    private static func categoryValue(_ value: ActivityCategory?) -> String? {
        switch value { case .game: "game"; case .meal: "meal"; case .call: "call"; case .work: "work"; case nil: nil }
    }
    private static func category(_ value: String) -> ActivityCategory? {
        switch value { case "game": .game; case "meal": .meal; case "call": .call; case "work": .work; default: nil }
    }
    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let value = try decoder.singleValueContainer().decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
    }
}
