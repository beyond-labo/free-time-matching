import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("Explicit demo dependencies")
struct AppFeatureDemoDependencyTests {
    @Test("明示デモ開始後のプロフィール保存は本番依存へ到達せずシードを表示する")
    func explicitDemoSavesProfileLocally() async {
        let scenario = HimatchPrototypeScenario(now: AvailabilityTestClock.now)
        var expected = await scenario.snapshot()
        expected.profileName = "デモ利用者"
        expected.profileIcon = PresetProfileIcon.sun.rawValue
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature(demoClient: scenario.client())
        } withDependencies: {
            $0.himatchClient = .productionPlaceholder
        }

        await store.send(.startDemo) {
            $0.isDemo = true
            $0.route = .profile
        }
        await store.send(.profileNameChanged("デモ利用者")) {
            $0.profileName = "デモ利用者"
        }
        await store.send(.saveProfileTapped) { $0.isLoading = true }
        await store.receive(\.profileSaved) {
            $0.snapshot = expected
            $0.isLoading = false
            $0.route = .main
        }
        #expect(store.state.snapshot?.hostings.isEmpty == false)
        #expect(store.state.snapshot?.invitations.isEmpty == false)
    }

    @Test("デモclientが注入されても本番セッションの再読込は本番clientを使う")
    func realSessionKeepsProductionBusinessClient() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "owner", accessToken: "access")
        state.snapshot = .empty()
        var production = HimatchClient.productionPlaceholder
        production.loadAvailability = { [] }
        let store = TestStore(initialState: state) {
            AppFeature(demoClient: HimatchPrototypeScenario(now: AvailabilityTestClock.now).client())
        } withDependencies: {
            $0.himatchClient = production
        }

        await store.send(.reloadAvailability) { $0.isAvailabilityLoading = true }
        await store.receive(\.availabilityLoaded) { $0.isAvailabilityLoading = false }
        #expect(store.state.snapshot?.availability.isEmpty == true)
        #expect(!store.state.isDemo)
    }

    @Test("プロフィールから誘うとホームのカレンダーでその友達を選択する")
    func invitingFriendFromProfileOpensHostingCalendar() async {
        var state = AppFeature.State()
        state.route = .main
        state.selectedTab = .friends
        let friendID = UUID(42)
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.inviteFriendFromProfile(friendID)) {
            $0.selectedTab = .home
            $0.homeTimeline.presentation = .calendar
            $0.homeTimeline.selectionMode = .hosting
            $0.selectedFriendIDs = [friendID]
        }
    }
}
