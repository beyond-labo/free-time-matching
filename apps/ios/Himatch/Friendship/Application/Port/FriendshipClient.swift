import Foundation

struct FriendshipClient: Sendable {
    var load: @Sendable (_ accessToken: String) async throws -> FriendshipSnapshot
    var rotateCode: @Sendable (_ accessToken: String) async throws -> FriendshipSnapshot
    var resolveCode: @Sendable (_ code: String, _ accessToken: String) async throws -> FriendProfile
    var sendRequest: @Sendable (_ code: String, _ operationID: UUID, _ accessToken: String) async throws -> FriendshipSnapshot
    var transitionRequest: @Sendable (
        _ requestID: UUID,
        _ transition: FriendRequestTransition,
        _ expectedVersion: Int,
        _ operationID: UUID,
        _ accessToken: String
    ) async throws -> FriendshipSnapshot
    var removeFriend: @Sendable (
        _ friendID: UUID,
        _ expectedVersion: Int,
        _ operationID: UUID,
        _ accessToken: String
    ) async throws -> FriendshipSnapshot
}

extension FriendshipClient {
    static func unconfigured(_ message: String) -> Self {
        Self(
            load: { _ in throw AuthenticationFailure.configuration(message) },
            rotateCode: { _ in throw AuthenticationFailure.configuration(message) },
            resolveCode: { _, _ in throw AuthenticationFailure.configuration(message) },
            sendRequest: { _, _, _ in throw AuthenticationFailure.configuration(message) },
            transitionRequest: { _, _, _, _, _ in throw AuthenticationFailure.configuration(message) },
            removeFriend: { _, _, _, _ in throw AuthenticationFailure.configuration(message) }
        )
    }
}
