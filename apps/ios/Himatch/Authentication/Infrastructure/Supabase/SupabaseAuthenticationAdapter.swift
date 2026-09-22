import Foundation
import Supabase

final class SupabaseAuthenticationAdapter: @unchecked Sendable {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func client() -> AuthenticationClient {
        AuthenticationClient(
            restoreSession: { [supabase] in
                guard supabase.auth.currentSession != nil else { return nil }
                do {
                    return Self.map(try await supabase.auth.session)
                } catch {
                    throw AuthenticationFailure.unavailable("サインイン状態を復元できませんでした。もう一度お試しください。")
                }
            },
            signInWithApple: { [supabase] credential in
                do {
                    let session = try await supabase.auth.signInWithIdToken(
                        credentials: .init(
                            provider: .apple,
                            idToken: credential.identityToken,
                            nonce: credential.rawNonce
                        )
                    )
                    return Self.map(session)
                } catch {
                    throw AuthenticationFailure.invalidAppleCredential
                }
            },
            signOut: { [supabase] in
                do {
                    try await supabase.auth.signOut(scope: .local)
                } catch {
                    throw AuthenticationFailure.unavailable("端末のサインイン状態を破棄できませんでした。")
                }
            },
            stateChanges: { [supabase] in
                AsyncStream { continuation in
                    let task = Task {
                        for await (_, session) in supabase.auth.authStateChanges {
                            if let session {
                                continuation.yield(.authenticated(Self.map(session)))
                            } else {
                                continuation.yield(.signedOut)
                            }
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }

    private static func map(_ session: Session) -> AuthenticationSession {
        AuthenticationSession(
            userID: session.user.id.uuidString,
            accessToken: session.accessToken
        )
    }
}
