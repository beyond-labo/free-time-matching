import Foundation

struct AccountDeletionAuthorization: Equatable, Sendable {
    let appleAuthorizationCode: String
    let operationID: UUID
    let accessToken: String
}

enum AccountDeletionResultStatus: String, Codable, Equatable, Sendable {
    case accepted
    case processing
    case completed
    case actionRequired
}

struct AccountDeletionReceipt: Equatable, Sendable {
    let reference: String
    let status: AccountDeletionResultStatus
    let statusToken: String
    let message: String?
}

struct PendingAccountDeletion: Codable, Equatable, Sendable {
    let reference: String
    let statusToken: String
}
