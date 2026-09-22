import ComposableArchitecture
import SwiftUI

@main
struct HimatchApp: App {
    static let displayName = "ひまっち"

    private let store: StoreOf<AppFeature>

    init() {
        store = AppCompositionRoot.makeStore()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
