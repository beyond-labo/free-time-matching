import Foundation

enum AppleCredentialDataDecoder {
    static func identityToken(_ data: Data?) throws -> String {
        try utf8(data)
    }

    static func authorizationCode(_ data: Data?) throws -> String {
        try utf8(data)
    }

    private static func utf8(_ data: Data?) throws -> String {
        guard let data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw AuthenticationFailure.invalidAppleCredential
        }
        return value
    }
}
