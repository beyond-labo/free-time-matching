import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("Explicit demo dependencies")
struct AppFeatureDemoDependencyTests {
    @Test("明示デモ開始後のプロフィール保存は本番依存へ到達せずシードを表示する")
    func explicitDemoSavesProfileLocally() async {
        let scenario = HimatchPrototypeScenario(now: AvailabilityTestClock.now, seed: .withFriends)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.himatchClient = .productionPlaceholder
            $0.demoScenarioClient = .live(scenario)
            $0.automaticSchedulingEffects = .routingDemo(live: .unconfigured, demo: $0.demoScenarioClient.scheduling)
            $0.firstMatchLocalStore = .inMemory()
        }
        store.exhaustivity = .off

        await store.send(.startDemo(.withFriends)) {
            $0.isDemo = true
            $0.route = .profile
        }
        await store.receive(\.demoSnapshotLoaded)
        await store.send(.profileNameChanged("デモ利用者")) {
            $0.profileName = "デモ利用者"
        }
        await store.send(.saveProfileTapped) { $0.isLoading = true }
        await store.receive(\.profileSaved) {
            $0.isLoading = false
            $0.route = .main
        }
        await store.receive(\.automaticScheduling.loaded)
        #expect(store.state.snapshot?.profileName == "デモ利用者")
        #expect(store.state.snapshot?.friends.isEmpty == false)
        #expect(store.state.automaticScheduling.ownerID == FirstMatchLocalStore.demoAccountKey)
        #expect(store.state.automaticScheduling.snapshot == .empty)
    }

    @Test("デモ依存が注入されても本番セッションの再読込は本番clientを使う")
    func realSessionKeepsProductionBusinessClient() async {
        var state = AppFeature.State()
        state.route = .main
        state.authenticationSession = AuthenticationSession(userID: "owner", accessToken: "access")
        state.snapshot = .empty()
        var production = HimatchClient.productionPlaceholder
        production.loadAvailability = { [] }
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.himatchClient = production
            $0.demoScenarioClient = .live(HimatchPrototypeScenario(now: AvailabilityTestClock.now))
        }

        await store.send(.reloadAvailability) { $0.isAvailabilityLoading = true }
        await store.receive(\.availabilityLoaded) { $0.isAvailabilityLoading = false }
        #expect(store.state.snapshot?.availability.isEmpty == true)
        #expect(!store.state.isDemo)
    }

    @Test("自動提案の依存は demo 所有者だけをデモへ振り分ける")
    func schedulingRoutesOnlyDemoOwner() async throws {
        var live = AutomaticSchedulingEffects.unconfigured
        live.load = { _ in SchedulingSnapshot(enabled: true, permissions: [], proposals: [], notifications: []) }
        let routed = AutomaticSchedulingEffects.routingDemo(
            live: live, demo: DemoScenarioClient.live(HimatchPrototypeScenario(now: AvailabilityTestClock.now)).scheduling
        )
        #expect(try await routed.load("8E0F0E5C-0000-0000-0000-000000000001").enabled)
        #expect(try await routed.load(FirstMatchLocalStore.demoAccountKey).enabled == false)
    }

    @Test("プロフィールから誘うとその友達を選んだお誘い作成を開く")
    func invitingFriendFromProfileOpensComposer() async {
        let friend = FriendProfile(id: UUID(42), displayName: "田中", icon: "sun.max.fill")
        var state = AppFeature.State()
        state.route = .main
        state.selectedTab = .friends
        state.snapshot = .empty()
        state.snapshot?.friends = [friend]
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.firstMatchLocalStore = .inMemory()
            $0.date.now = AvailabilityTestClock.now
            $0.calendar = AvailabilityTestClock.calendar
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.inviteFriendFromProfile(friend.id))
        await store.receive(\.startInvitation) { $0.selectedTab = .home }
        #expect(store.state.composer?.selectedFriendIDs == [friend.id])
    }
}
