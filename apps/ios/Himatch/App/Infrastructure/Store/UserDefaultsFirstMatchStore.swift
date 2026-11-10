import Foundation

extension FirstMatchLocalStore {
    /// Stores one JSON value per account under `firstMatch.<accountKey>`. Read failures fall back to the default record.
    static func userDefaults(_ defaults: UserDefaults = .standard) -> Self {
        let box = UncheckedDefaults(defaults)
        @Sendable func storageKey(_ accountKey: String) -> String { "firstMatch.\(accountKey)" }
        return Self(
            load: { accountKey in
                guard let data = box.defaults.data(forKey: storageKey(accountKey)),
                      let record = try? JSONDecoder().decode(FirstMatchRecord.self, from: data)
                else { return FirstMatchRecord() }
                return record
            },
            save: { accountKey, record in
                guard let data = try? JSONEncoder().encode(record) else { return }
                box.defaults.set(data, forKey: storageKey(accountKey))
            },
            remove: { accountKey in
                box.defaults.removeObject(forKey: storageKey(accountKey))
            }
        )
    }
}

/// UserDefaults is thread-safe but not marked Sendable.
private struct UncheckedDefaults: @unchecked Sendable {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults) { self.defaults = defaults }
}
