import Foundation

struct AuthenticationClient: Sendable {
    var restoreSession: @Sendable () async throws -> AuthenticationSession?
    var signInWithApple: @Sendable (AppleAuthorizationCredential) async throws -> AuthenticationSession
    var signOut: @Sendable () async throws -> Void
    var stateChanges: @Sendable () -> AsyncStream<AuthenticationStateChange>
}

extension AuthenticationClient {
    static func unconfigured(_ message: String) -> Self {
        Self(
            restoreSession: { throw AuthenticationFailure.configuration(message) },
            signInWithApple: { _ in throw AuthenticationFailure.configuration(message) },
            signOut: {},
            stateChanges: { AsyncStream { $0.finish() } }
        )
    }
}
