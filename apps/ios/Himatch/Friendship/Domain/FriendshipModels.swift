import Foundation

struct FriendProfile: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var icon: String
    var relationshipVersion: Int? = nil
}

struct FriendRequest: Equatable, Codable, Identifiable, Sendable {
    enum Direction: String, Codable, Equatable, Sendable {
        case incoming
        case outgoing
    }

    let id: UUID
    var person: FriendProfile
    var direction: Direction
    var version: Int = 1
}

struct InviteCode: Equatable, Codable, Sendable {
    var value: String
    var expiresAt: Date
}

struct FriendshipSnapshot: Equatable, Sendable {
    var inviteCode: InviteCode?
    var friends: [FriendProfile]
    var requests: [FriendRequest]
}

enum FriendRequestTransition: String, Equatable, Sendable {
    case accept
    case reject
    case cancel
}
