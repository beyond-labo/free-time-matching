import ComposableArchitecture
import SwiftUI

@main
struct HimatchApp: App {
    @UIApplicationDelegateAdaptor(SchedulingAppDelegate.self) private var appDelegate
    static let displayName = "アイマノ"

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
