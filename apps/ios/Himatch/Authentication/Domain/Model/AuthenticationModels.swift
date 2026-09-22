import Foundation

struct AppleAuthorizationCredential: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
}

struct AuthenticationSession: Equatable, Sendable {
    let userID: String
    let accessToken: String
}

enum AuthenticationStateChange: Equatable, Sendable {
    case authenticated(AuthenticationSession)
    case signedOut
}

enum AuthenticationFailure: LocalizedError, Equatable, Sendable {
    case cancelled
    case invalidAppleCredential
    case configuration(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Appleでサインインをキャンセルしました。"
        case .invalidAppleCredential:
            "Appleの認証情報を確認できませんでした。もう一度お試しください。"
        case let .configuration(message), let .unavailable(message):
            message
        }
    }
}
