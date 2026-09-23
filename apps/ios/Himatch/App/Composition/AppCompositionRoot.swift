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
        } catch {
            let message = error.localizedDescription
            authentication = .unconfigured(message)
            profile = .unconfigured(message)
            deletion = .unconfigured(message)
            friendship = .unconfigured(message)
        }

        let business: HimatchClient
#if DEBUG
        business = HimatchPrototypeScenario().client()
#else
        business = .productionPlaceholder
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
}
