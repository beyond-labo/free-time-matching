import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("App feature")
struct AppFeatureTests {
    @Test("初期状態は利用説明とホームタブを示す")
    func initialRouteAndTab() {
        let state = AppFeature.State()

        #expect(state.route == .onboarding)
        #expect(state.selectedTab == .home)
        #expect(state.availabilityVisibility == .privateUntilAccepted)
        #expect(!state.reminderEnabled)
    }

    @Test("プロフィール保存結果を共有シナリオから取得できる")
    func profileCanBeSavedThroughInjectedBoundary() async throws {
        let scenario = HimatchPrototypeScenario(now: Date(timeIntervalSince1970: 2_000_000_000))
        let saved = try await scenario.client().saveProfile("テストユーザー", "star.fill")

        #expect(saved.profileName == "テストユーザー")
        #expect(saved.profileIcon == "star.fill")
    }
}
