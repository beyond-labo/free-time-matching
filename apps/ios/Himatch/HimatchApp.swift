import ComposableArchitecture
import SwiftUI

@main
struct HimatchApp: App {
    static let displayName = "ひまっち"

    private let store: StoreOf<AppFeature>

    init() {
        let scenario = HimatchPrototypeScenario()
        store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.himatchClient = scenario.client()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
