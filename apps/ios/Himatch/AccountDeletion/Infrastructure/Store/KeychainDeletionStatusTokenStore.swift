import Foundation
import Security

struct KeychainDeletionStatusTokenStore {
    private static let pendingAccount = "pending"
    private static let operationAccount = "operation-id"
    private let service: String

    init(service: String = "com.beyond-labo.himatch.account-deletion") {
        self.service = service
    }

    func client() -> DeletionStatusTokenStore {
        DeletionStatusTokenStore(
            save: { [service] pending in
                let data = try JSONEncoder().encode(pending)
                try Self.save(data, service: service, account: Self.pendingAccount)
            },
            load: { [service] in
                guard let data = try Self.load(service: service, account: Self.pendingAccount) else { return nil }
                return try JSONDecoder().decode(PendingAccountDeletion.self, from: data)
            },
            remove: { [service] in
                try Self.remove(service: service, account: Self.pendingAccount)
            },
            saveOperationID: { [service] operationID in
                try Self.save(Data(operationID.uuidString.utf8), service: service, account: Self.operationAccount)
            },
            loadOperationID: { [service] in
                guard
                    let data = try Self.load(service: service, account: Self.operationAccount),
                    let value = String(data: data, encoding: .utf8),
                    let operationID = UUID(uuidString: value)
                else { return nil }
                return operationID
            },
            removeOperationID: { [service] in
                try Self.remove(service: service, account: Self.operationAccount)
            }
        )
    }

    private static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainTokenError.status(status) }
    }

    private static func load(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainTokenError.status(status)
        }
        return data
    }

    private static func remove(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenError.status(status)
        }
    }
}

enum KeychainTokenError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        "削除状況を端末へ安全に保存できませんでした。"
    }
}
