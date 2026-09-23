import ComposableArchitecture

private enum HimatchClientKey: DependencyKey {
    static let liveValue = HimatchClient.productionPlaceholder
    static let testValue = liveValue
}

private enum AuthenticationClientKey: DependencyKey {
    static let liveValue = AuthenticationClient.unconfigured("AuthenticationClient is not injected")
    static let testValue = liveValue
}

private enum FriendshipClientKey: DependencyKey {
    static let liveValue = FriendshipClient.unconfigured("FriendshipClient is not injected")
    static let testValue = liveValue
}

private enum ProfileClientKey: DependencyKey {
    static let liveValue = ProfileClient.unconfigured("ProfileClient is not injected")
    static let testValue = liveValue
}

private enum AccountDeletionClientKey: DependencyKey {
    static let liveValue = AccountDeletionClient.unconfigured("AccountDeletionClient is not injected")
    static let testValue = liveValue
}

private enum DeletionStatusTokenStoreKey: DependencyKey {
    static let liveValue = DeletionStatusTokenStore.noop
    static let testValue = liveValue
}

extension DependencyValues {
    var himatchClient: HimatchClient {
        get { self[HimatchClientKey.self] }
        set { self[HimatchClientKey.self] = newValue }
    }

    var authenticationClient: AuthenticationClient {
        get { self[AuthenticationClientKey.self] }
        set { self[AuthenticationClientKey.self] = newValue }
    }

    var friendshipClient: FriendshipClient {
        get { self[FriendshipClientKey.self] }
        set { self[FriendshipClientKey.self] = newValue }
    }

    var profileClient: ProfileClient {
        get { self[ProfileClientKey.self] }
        set { self[ProfileClientKey.self] = newValue }
    }

    var accountDeletionClient: AccountDeletionClient {
        get { self[AccountDeletionClientKey.self] }
        set { self[AccountDeletionClientKey.self] = newValue }
    }

    var deletionStatusTokenStore: DeletionStatusTokenStore {
        get { self[DeletionStatusTokenStoreKey.self] }
        set { self[DeletionStatusTokenStoreKey.self] = newValue }
    }
}
