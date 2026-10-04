import Foundation

struct SystemActionJournalClient: Sendable {
    var records: @Sendable () async throws -> [SystemActionRecord]
    var save: @Sendable (SystemActionRecord) async throws -> Void
    var remove: @Sendable (UUID) async throws -> Void
}

struct SystemActionDependencies: Sendable {
    /// Restores session, verifies deletion gate and profile, and returns the authenticated owner.
    var authenticatedOwner: @Sendable () async throws -> String
    var businessClientForOwner: @Sendable (String) -> HimatchClient
    var friendsForOwner: @Sendable (String) async throws -> [FriendProfile]
    var protectedDataAvailable: @Sendable () async -> Bool
    var journal: SystemActionJournalClient
    var restoredOwnerID: @Sendable () async throws -> String? = { nil }
    var now: @Sendable () -> Date = { Date() }
    var uuid: @Sendable () -> UUID = { UUID() }
}
