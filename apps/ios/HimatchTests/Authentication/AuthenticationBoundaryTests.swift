import Foundation
import Testing
@testable import Himatch

@Suite("Authentication boundary")
struct AuthenticationBoundaryTests {
    @Test("Apple nonce is SHA256 hex and generated values have requested length")
    func nonceGenerationAndHashing() throws {
        let nonce = try AppleNonce.generate(length: 32)

        #expect(nonce.count == 32)
        #expect(AppleNonce.sha256("nonce") == "78377b525757b494427f89014f97d79928f3938d14eb51e20fb5dec9834eb304")
    }

    @Test("Apple authorization code is decoded as UTF-8, not Base64")
    func authorizationCodeUsesUTF8() throws {
        let data = Data("apple-code.value".utf8)

        #expect(try AppleCredentialDataDecoder.authorizationCode(data) == "apple-code.value")
        #expect(try AppleCredentialDataDecoder.authorizationCode(data) != data.base64EncodedString())
    }

    @Test("Invalid Apple credential bytes are rejected")
    func invalidCredentialBytesAreRejected() {
        #expect(throws: AuthenticationFailure.invalidAppleCredential) {
            try AppleCredentialDataDecoder.identityToken(Data([0xff]))
        }
    }
}
