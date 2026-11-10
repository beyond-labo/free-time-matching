#if DEBUG
import ComposableArchitecture
import Foundation

enum DemoSeed: Equatable, Sendable {
    case noFriends
    case withFriends

    var scenarioSeed: HimatchPrototypeScenario.Seed {
        switch self {
        case .noFriends: .noFriends
        case .withFriends: .withFriends
        }
    }
}

/// DEBUG-only access to the prototype scenario for the explicit demo (requirement 10).
/// Release builds contain neither this client nor the scenario.
struct DemoScenarioClient: Sendable {
    var business: HimatchClient
    var reset: @Sendable (DemoSeed) async -> AppSnapshot
    var simulateFriendRequest: @Sendable () async -> AppSnapshot
    var simulateAcceptance: @Sendable (_ hostingID: UUID) async -> AppSnapshot
    var scheduling: AutomaticSchedulingEffects
    var simulateProposal: @Sendable () async -> SchedulingSnapshot
    var simulatePeerAcceptance: @Sendable (_ proposalID: UUID) async -> SchedulingSnapshot

    static func live(_ scenario: HimatchPrototypeScenario) -> Self {
        var business = scenario.client()
        let accept = business.acceptRequest
        business.acceptRequest = { id in
            _ = await accept(id)
            return await scenario.connectDemoFriends()
        }
        return Self(
            business: business,
            reset: { seed in
                await scenario.reset(seed: seed.scenarioSeed)
                return await scenario.snapshot()
            },
            simulateFriendRequest: { await scenario.simulateFriendRequest() },
            simulateAcceptance: { await scenario.simulateAcceptance(hostingID: $0) },
            scheduling: AutomaticSchedulingEffects(
                load: { _ in await scenario.schedulingSnapshot() },
                execute: { command, _, _ in try await scenario.executeScheduling(command) },
                requestNotifications: { _ in false },
                synchronizeDevice: { _ in },
                disableDevice: { _ in }
            ),
            simulateProposal: { await scenario.simulateProposal() },
            simulatePeerAcceptance: { await scenario.simulatePeerAcceptance(proposalID: $0) }
        )
    }
}

extension AutomaticSchedulingEffects {
    /// Routes the explicit demo owner to the prototype scenario and every real account to the live effects.
    static func routingDemo(live: AutomaticSchedulingEffects, demo: AutomaticSchedulingEffects) -> Self {
        let key = FirstMatchLocalStore.demoAccountKey
        return Self(
            load: { owner in try await (owner == key ? demo : live).load(owner) },
            execute: { command, operationID, owner in try await (owner == key ? demo : live).execute(command, operationID, owner) },
            requestNotifications: { owner in try await (owner == key ? demo : live).requestNotifications(owner) },
            synchronizeDevice: { owner in try await (owner == key ? demo : live).synchronizeDevice(owner) },
            disableDevice: { owner in try await (owner == key ? demo : live).disableDevice(owner) }
        )
    }
}

private enum DemoScenarioClientKey: DependencyKey {
    static let liveValue = DemoScenarioClient.live(HimatchPrototypeScenario(seed: .noFriends))
    static var testValue: DemoScenarioClient { .live(HimatchPrototypeScenario(seed: .noFriends)) }
}

extension DependencyValues {
    var demoScenarioClient: DemoScenarioClient {
        get { self[DemoScenarioClientKey.self] }
        set { self[DemoScenarioClientKey.self] = newValue }
    }
}
#endif
