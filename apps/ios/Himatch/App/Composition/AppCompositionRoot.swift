import ComposableArchitecture
import Foundation

@MainActor
enum AppCompositionRoot {
    static func makeStore(bundle: Bundle = .main) -> StoreOf<AppFeature> {
        makeStore(runtime: bundle == .main ? .shared : AppRuntime(bundle: bundle))
    }

    static func makeStore(runtime: AppRuntime) -> StoreOf<AppFeature> {
        Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authenticationClient = runtime.authentication
            $0.profileClient = runtime.profile
            $0.accountDeletionClient = runtime.deletion
            $0.friendshipClient = runtime.friendship
            $0.deletionStatusTokenStore = runtime.deletionStore
            $0.himatchClient = runtime.business
            $0.automaticSchedulingEffects = runtime.schedulingEffects
#if DEBUG
            // The explicit demo owner is served by the prototype scenario; real accounts use the live effects.
            $0.automaticSchedulingEffects = .routingDemo(live: runtime.schedulingEffects, demo: $0.demoScenarioClient.scheduling)
#endif
            let service = runtime.systemActions
            $0.systemActionHandoffClient = SystemActionHandoffClient(
                pendingOperationID: { try? await service.pendingHandoff()?.operationID },
                invalidate: { owner in try? await service.invalidate(ownerUserID: owner) }
            )
        }
    }
}
