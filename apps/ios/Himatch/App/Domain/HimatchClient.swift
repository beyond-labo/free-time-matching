import Foundation

struct AppSnapshot: Equatable, Sendable {
    var profileName: String
    var profileIcon: String
    var inviteCode: InviteCode?
    var availability: [AvailabilitySlot]
    var friends: [FriendProfile]
    var requests: [FriendRequest]
    var hostings: [Hosting]
    var invitations: [Hosting]
    var plans: [ConfirmedPlan]
    var blocked: [FriendProfile]
    var deletionStatus: AccountDeletionStatus
}

struct HostingDraft: Equatable, Sendable {
    var mode: HostingMode
    var area: HostingArea?
    var category: ActivityCategory?
    var start: Date
    var duration: TimeInterval
    var friends: [FriendProfile]
}

struct HimatchClient: Sendable {
    var load: @Sendable () async -> AppSnapshot
    var loadAvailability: @Sendable () async throws -> [AvailabilitySlot]
    var saveProfile: @Sendable (String, String) async throws -> AppSnapshot
    var addAvailability: @Sendable (AvailabilitySlot) async throws -> AppSnapshot
    var removeAvailability: @Sendable (UUID) async throws -> AppSnapshot
    var createHosting: @Sendable (HostingDraft) async throws -> AppSnapshot
    var acceptInvitation: @Sendable (UUID, TimeIntervalRange) async throws -> AppSnapshot
    var confirmHosting: @Sendable (UUID) async throws -> AppSnapshot
    var acceptRequest: @Sendable (UUID) async -> AppSnapshot
    var removeFriend: @Sendable (UUID) async -> AppSnapshot
    var submitReport: @Sendable (ReportReason, String) async throws -> ReportReceipt
    var block: @Sendable (UUID) async -> AppSnapshot
    var deleteAccount: @Sendable () async -> AppSnapshot
}

extension AppSnapshot {
    static func empty(profileName: String = "", profileIcon: String = PresetProfileIcon.sun.rawValue) -> Self {
        Self(
            profileName: profileName,
            profileIcon: profileIcon,
            inviteCode: nil,
            availability: [],
            friends: [],
            requests: [],
            hostings: [],
            invitations: [],
            plans: [],
            blocked: [],
            deletionStatus: .idle
        )
    }

    static func empty(availability: [AvailabilitySlot]) -> Self {
        var snapshot = Self.empty()
        snapshot.availability = availability
        return snapshot
    }

    mutating func apply(_ friendship: FriendshipSnapshot) {
        inviteCode = friendship.inviteCode
        friends = friendship.friends
        requests = friendship.requests
    }
}

extension HimatchClient {
    static let productionPlaceholder = Self(
        load: { .empty() },
        loadAvailability: { throw PrototypeError.notFound },
        saveProfile: { _, _ in throw PrototypeError.notFound },
        addAvailability: { _ in throw PrototypeError.notFound },
        removeAvailability: { _ in .empty() },
        createHosting: { _ in throw PrototypeError.notFound },
        acceptInvitation: { _, _ in throw PrototypeError.notFound },
        confirmHosting: { _ in throw PrototypeError.notFound },
        acceptRequest: { _ in .empty() },
        removeFriend: { _ in .empty() },
        submitReport: { _, _ in throw PrototypeError.notFound },
        block: { _ in .empty() },
        deleteAccount: { .empty() }
    )
}
