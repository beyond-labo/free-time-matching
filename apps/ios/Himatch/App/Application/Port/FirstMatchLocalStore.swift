import ComposableArchitecture
import Foundation

/// Device-local, per-account record for the first-match guide, last meeting style and seen 参加OK keys.
/// `accountKey` is the authenticated internal user ID (or `demo`), never a display name.
struct FirstMatchLocalStore: Sendable {
    var load: @Sendable (_ accountKey: String) -> FirstMatchRecord
    var save: @Sendable (_ accountKey: String, _ record: FirstMatchRecord) -> Void
    var remove: @Sendable (_ accountKey: String) -> Void

    static let demoAccountKey = "demo"

    /// Ignores writes; every read returns the default record.
    static let noop = Self(load: { _ in FirstMatchRecord() }, save: { _, _ in }, remove: { _ in })

    static func inMemory() -> Self {
        let storage = LockIsolated<[String: FirstMatchRecord]>([:])
        return Self(
            load: { key in storage.value[key] ?? FirstMatchRecord() },
            save: { key, record in storage.withValue { $0[key] = record } },
            remove: { key in storage.withValue { $0[key] = nil } }
        )
    }
}

private enum FirstMatchLocalStoreKey: DependencyKey {
    static let liveValue = FirstMatchLocalStore.userDefaults()
    static let testValue = FirstMatchLocalStore.noop
}

extension DependencyValues {
    var firstMatchLocalStore: FirstMatchLocalStore {
        get { self[FirstMatchLocalStoreKey.self] }
        set { self[FirstMatchLocalStoreKey.self] = newValue }
    }
}
