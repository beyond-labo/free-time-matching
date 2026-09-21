import Foundation

struct FriendProfile: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var icon: String
}

struct FriendRequest: Equatable, Codable, Identifiable, Sendable {
    enum Direction: String, Codable, Equatable, Sendable {
        case incoming
        case outgoing
    }

    let id: UUID
    var person: FriendProfile
    var direction: Direction
}

struct InviteCode: Equatable, Codable, Sendable {
    var value: String
    var expiresAt: Date
}
