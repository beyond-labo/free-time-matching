import Foundation

struct AccountDeletionClient: Sendable {
    var submit: @Sendable (AccountDeletionAuthorization) async throws -> AccountDeletionReceipt
    var status: @Sendable (PendingAccountDeletion) async throws -> AccountDeletionReceipt
}

extension AccountDeletionClient {
    static func unconfigured(_ message: String) -> Self {
        Self(
            submit: { _ in throw AuthenticationFailure.configuration(message) },
            status: { _ in throw AuthenticationFailure.configuration(message) }
        )
    }
}

struct DeletionStatusTokenStore: Sendable {
    var save: @Sendable (PendingAccountDeletion) throws -> Void
    var load: @Sendable () throws -> PendingAccountDeletion?
    var remove: @Sendable () throws -> Void
    var saveOperationID: @Sendable (UUID) throws -> Void
    var loadOperationID: @Sendable () throws -> UUID?
    var removeOperationID: @Sendable () throws -> Void

    init(
        save: @escaping @Sendable (PendingAccountDeletion) throws -> Void,
        load: @escaping @Sendable () throws -> PendingAccountDeletion?,
        remove: @escaping @Sendable () throws -> Void,
        saveOperationID: @escaping @Sendable (UUID) throws -> Void = { _ in },
        loadOperationID: @escaping @Sendable () throws -> UUID? = { nil },
        removeOperationID: @escaping @Sendable () throws -> Void = {}
    ) {
        self.save = save
        self.load = load
        self.remove = remove
        self.saveOperationID = saveOperationID
        self.loadOperationID = loadOperationID
        self.removeOperationID = removeOperationID
    }
}

extension DeletionStatusTokenStore {
    static let noop = Self(save: { _ in }, load: { nil }, remove: {})
}
