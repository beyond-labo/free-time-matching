import AppIntents
import Foundation

enum SystemActionEntityID {
    static func make(owner: String, target: UUID) -> String { "\(owner):\(target.uuidString)" }
    static func parse(_ value: String) -> (owner: String, target: UUID)? {
        guard let separator = value.lastIndex(of: ":"),
              let target = UUID(uuidString: String(value[value.index(after: separator)...])) else { return nil }
        let owner = String(value[..<separator])
        return owner.isEmpty ? nil : (owner, target)
    }
}

struct FriendEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "友達"
    static let defaultQuery = FriendEntityQuery()
    var ownerUserID: String
    var userID: UUID
    var nickname: String
    var presetIconKey: String
    var id: String { SystemActionEntityID.make(owner: ownerUserID, target: userID) }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(nickname)", subtitle: "\(String(userID.uuidString.prefix(8)))",
                              image: .init(systemName: PresetProfileIcon(rawValue: presetIconKey)?.rawValue ?? "person.crop.circle"))
    }
}

struct FriendEntityQuery: EntityStringQuery {
    static func resolve(_ identifiers: [String], candidates: [FriendEntity]) -> [FriendEntity] {
        identifiers.compactMap { id in candidates.first { $0.id == id } }
    }
    func entities(for identifiers: [String]) async throws -> [FriendEntity] {
        let candidates = try await suggestedEntities()
        return Self.resolve(identifiers, candidates: candidates)
    }
    func entities(matching string: String) async throws -> [FriendEntity] {
        try await suggestedEntities().filter { $0.nickname.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [FriendEntity] {
        let service = await AppRuntime.shared.systemActions
        guard let result = try? await service.queryFriends() else { return [] }
        return result.friends.map {
            FriendEntity(ownerUserID: result.ownerUserID, userID: $0.id, nickname: $0.displayName, presetIconKey: $0.icon)
        }
    }
}

struct OwnedHostingEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "自分の募集"
    static let defaultQuery = OwnedHostingEntityQuery()
    var ownerUserID: String
    var hostingID: UUID
    var start: Date
    var end: Date
    var mode: HostingMode
    var category: ActivityCategory?
    var area: HostingArea?
    var id: String { SystemActionEntityID.make(owner: ownerUserID, target: hostingID) }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(SystemActionIntentText.interval(start: start, end: end))",
                              subtitle: "\(SystemActionIntentText.conditions(mode: mode, category: category, area: area))")
    }
}

struct OwnedHostingEntityQuery: EntityStringQuery {
    static func candidates(ownerUserID: String, hostings: [Hosting]) -> [OwnedHostingEntity] {
        hostings.filter { $0.isHostedByMe && $0.status == .recruiting }.map {
            OwnedHostingEntity(ownerUserID: ownerUserID, hostingID: $0.id,
                               start: $0.candidateRange.start, end: $0.candidateRange.end,
                               mode: $0.mode, category: $0.category, area: $0.area)
        }
    }
    func entities(for identifiers: [String]) async throws -> [OwnedHostingEntity] {
        let candidates = try await suggestedEntities()
        return identifiers.compactMap { id in candidates.first { $0.id == id } }
    }
    func entities(matching string: String) async throws -> [OwnedHostingEntity] {
        try await suggestedEntities().filter {
            SystemActionIntentText.interval(start: $0.start, end: $0.end).localizedCaseInsensitiveContains(string)
                || $0.mode.rawValue.localizedCaseInsensitiveContains(string)
                || ($0.category?.rawValue.localizedCaseInsensitiveContains(string) ?? false)
        }
    }
    func suggestedEntities() async throws -> [OwnedHostingEntity] {
        let service = await AppRuntime.shared.systemActions
        guard let result = try? await service.queryHostings() else { return [] }
        return Self.candidates(ownerUserID: result.ownerUserID, hostings: result.hostings)
    }
}
