import Foundation

struct ProfileClient: Sendable {
    var get: @Sendable (_ accessToken: String) async throws -> UserProfile?
    var put: @Sendable (_ nickname: String, _ presetIcon: PresetProfileIcon, _ accessToken: String) async throws -> UserProfile
}

extension ProfileClient {
    static func unconfigured(_ message: String) -> Self {
        Self(
            get: { _ in throw AuthenticationFailure.configuration(message) },
            put: { _, _, _ in throw AuthenticationFailure.configuration(message) }
        )
    }
}
