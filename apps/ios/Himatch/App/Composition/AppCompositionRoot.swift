import ComposableArchitecture
import Foundation
import Supabase

@MainActor
enum AppCompositionRoot {
    static func makeStore(bundle: Bundle = .main) -> StoreOf<AppFeature> {
        let authentication: AuthenticationClient
        let profile: ProfileClient
        let deletion: AccountDeletionClient
        let friendship: FriendshipClient
        let availability: BackendAvailabilityAdapter
        let hosting: BackendHostingAdapter

        do {
            let configuration = try AppConfiguration(bundle: bundle)
            let supabase = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.supabasePublishableKey
            )
            authentication = SupabaseAuthenticationAdapter(supabase: supabase).client()
            profile = BackendProfileAdapter(baseURL: configuration.apiBaseURL).client()
            deletion = BackendAccountDeletionAdapter(baseURL: configuration.apiBaseURL).client()
            friendship = BackendFriendshipAdapter(baseURL: configuration.apiBaseURL).client()
            availability = BackendAvailabilityAdapter(baseURL: configuration.apiBaseURL)
            hosting = BackendHostingAdapter(baseURL: configuration.apiBaseURL)
        } catch {
            let message = error.localizedDescription
            authentication = .unconfigured(message)
            profile = .unconfigured(message)
            deletion = .unconfigured(message)
            friendship = .unconfigured(message)
            availability = BackendAvailabilityAdapter(baseURL: URL(string: "https://invalid.local/")!)
            hosting = BackendHostingAdapter(baseURL: URL(string: "https://invalid.local/")!)
        }

        let business: HimatchClient
#if DEBUG
        business = HimatchPrototypeScenario().client()
#else
        business = Self.productionBusiness(authentication: authentication, availability: availability, hosting: hosting)
#endif

        return Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authenticationClient = authentication
            $0.profileClient = profile
            $0.accountDeletionClient = deletion
            $0.friendshipClient = friendship
            $0.deletionStatusTokenStore = KeychainDeletionStatusTokenStore().client()
            $0.himatchClient = business
        }
    }

    private static func productionBusiness(
        authentication: AuthenticationClient,
        availability: BackendAvailabilityAdapter,
        hosting: BackendHostingAdapter
    ) -> HimatchClient {
        var client = HimatchClient.productionPlaceholder
        client.loadAvailability = {
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            return try await availability.load(accessToken: session.accessToken)
        }
        client.addAvailability = { slot in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            return AppSnapshot.empty(availability: try await availability.put(slot, accessToken: session.accessToken))
        }
        client.removeAvailability = { id in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            return AppSnapshot.empty(availability: try await availability.delete(id: id, accessToken: session.accessToken))
        }
        client.subtractAvailability = { interval, operationID in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            return AppSnapshot.empty(availability: try await availability.subtract(interval, operationID: operationID, accessToken: session.accessToken))
        }
        client.loadHostings = {
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            return try await hosting.load(accessToken: session.accessToken)
        }
        client.createHosting = { draft in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            let created = try await hosting.create(draft, operationID: draft.operationID, accessToken: session.accessToken)
            let availabilitySlots = try await availability.load(accessToken: session.accessToken)
            var snapshot = AppSnapshot.empty(availability: availabilitySlots)
            snapshot.hostings = created.isHostedByMe ? [created] : []
            snapshot.invitations = created.isHostedByMe ? [] : [created]
            return snapshot
        }
        client.respondInvitation = { id, status, intervals, operationID, version in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            let response = try await hosting.respond(id: id, status: status, intervals: intervals,
                                                    operationID: operationID, expectedVersion: version,
                                                    accessToken: session.accessToken)
            var snapshot = AppSnapshot.empty(availability: try await availability.load(accessToken: session.accessToken))
            snapshot.invitations = response.isHostedByMe ? [] : [response]
            snapshot.hostings = response.isHostedByMe ? [response] : []
            return snapshot
        }
        client.cancelHosting = { id, operationID, version in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            let cancelled = try await hosting.cancel(id: id, operationID: operationID, expectedVersion: version,
                                                     accessToken: session.accessToken)
            var snapshot = AppSnapshot.empty(availability: try await availability.load(accessToken: session.accessToken))
            snapshot.hostings = [cancelled]
            return snapshot
        }
        return client
    }
}
