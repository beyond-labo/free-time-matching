import Foundation
import OSLog

/// Authenticated HTTP adapter for the user's own availability projection.
/// The adapter deliberately exposes only the owner's slots; it never accepts or
/// logs credentials beyond placing the access token in the request header.
final class BackendAvailabilityAdapter: @unchecked Sendable {
    private struct Input: Encodable {
        let start: Date
        let end: Date
        let category: String?
        let visibility: String
    }

    private struct Payload: Decodable {
        let id: UUID
        let start: Date
        let end: Date
        let category: String?
        let visibility: String
    }

    private struct Collection: Decodable {
        let slots: [Payload]
    }

    private struct SlotResponse: Decodable {
        let slot: Payload
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let signposter = OSSignposter(subsystem: "Himatch", category: "Availability")
    private let logger = Logger(subsystem: "Himatch", category: "Availability")

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

    func load(accessToken: String) async throws -> [AvailabilitySlot] {
        try await decodeSlots(request(path: "v1/availability", method: "GET", accessToken: accessToken))
    }

    func put(_ slot: AvailabilitySlot, accessToken: String) async throws -> [AvailabilitySlot] {
        var request = try authorizedRequest(
            path: "v1/availability/\(slot.id.uuidString)",
            method: "PUT",
            accessToken: accessToken
        )
        request.httpBody = try encoder.encode(Input(
            start: slot.interval.start,
            end: slot.interval.end,
            category: Self.categoryValue(slot.category),
            visibility: slot.visibility.rawValue
        ))
        let data = try await responseData(for: request)
        _ = try decoder.decode(SlotResponse.self, from: data).slot
        return try await load(accessToken: accessToken)
    }

    func delete(id: UUID, accessToken: String) async throws -> [AvailabilitySlot] {
        _ = try await responseData(for: authorizedRequest(
            path: "v1/availability/\(id.uuidString)",
            method: "DELETE",
            accessToken: accessToken
        ))
        return try await load(accessToken: accessToken)
    }

    private func request(path: String, method: String, accessToken: String) async throws -> Data {
        try await responseData(for: authorizedRequest(path: path, method: method, accessToken: accessToken))
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let interval = signposter.beginInterval("AvailabilityHTTP")
        defer { signposter.endInterval("AvailabilityHTTP", interval) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }
        if let requestID = http.value(forHTTPHeaderField: "X-Request-ID") {
            logger.info("Availability request \(requestID, privacy: .public) completed with status \(http.statusCode)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendClientError.response(http.statusCode, Self.message(data))
        }
        return data
    }

    private func decodeSlots(_ data: Data) throws -> [AvailabilitySlot] {
        if let collection = try? decoder.decode(Collection.self, from: data) {
            return try collection.slots.map(Self.map)
        }
        return try decoder.decode([Payload].self, from: data).map(Self.map)
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

    private static func map(_ payload: Payload) throws -> AvailabilitySlot {
        let category: ActivityCategory?
        if let raw = payload.category {
            guard let value = Self.category(raw) else { throw BackendClientError.invalidResponse }
            category = value
        } else {
            category = nil
        }
        guard let visibility = AvailabilityVisibility(rawValue: payload.visibility) else {
            throw BackendClientError.invalidResponse
        }
        return AvailabilitySlot(
            id: payload.id,
            interval: TimeIntervalRange(id: payload.id, start: payload.start, end: payload.end),
            category: category,
            visibility: visibility
        )
    }

    private static func categoryValue(_ category: ActivityCategory?) -> String? {
        switch category {
        case .game: "game"
        case .meal: "meal"
        case .call: "call"
        case .work: "work"
        case nil: nil
        }
    }

    private static func category(_ raw: String) -> ActivityCategory? {
        switch raw {
        case "game", "ゲーム": .game
        case "meal", "ご飯": .meal
        case "call", "通話": .call
        case "work", "作業": .work
        default: nil
        }
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

    private static func message(_ data: Data) -> String? {
        (try? JSONDecoder().decode(BackendErrorPayload.self, from: data))?.message
    }
}
