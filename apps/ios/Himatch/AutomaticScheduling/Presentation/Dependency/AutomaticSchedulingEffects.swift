import ComposableArchitecture
import Foundation

/// Presentation-facing use case entry points. Composition binds a fresh token to the expected owner.
struct AutomaticSchedulingEffects: Sendable {
    var load: @Sendable (String) async throws -> SchedulingSnapshot
    var execute: @Sendable (SchedulingCommand, UUID, String) async throws -> SchedulingSnapshot
    var requestNotifications: @Sendable (String) async throws -> Bool
    var synchronizeDevice: @Sendable (String) async throws -> Void
    var disableDevice: @Sendable (String) async throws -> Void

    static let unconfigured = Self(
        load: { _ in throw SchedulingFailure.unavailable },
        execute: { _, _, _ in throw SchedulingFailure.unavailable },
        requestNotifications: { _ in throw SchedulingFailure.unavailable },
        synchronizeDevice: { _ in }, disableDevice: { _ in }
    )
}

private enum AutomaticSchedulingEffectsKey: DependencyKey {
    static let liveValue = AutomaticSchedulingEffects.unconfigured
    static let testValue = liveValue
}

extension DependencyValues {
    var automaticSchedulingEffects: AutomaticSchedulingEffects {
        get { self[AutomaticSchedulingEffectsKey.self] }
        set { self[AutomaticSchedulingEffectsKey.self] = newValue }
    }
}
