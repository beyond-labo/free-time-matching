import ComposableArchitecture
import Foundation
import Supabase
import UIKit

/// One real dependency graph for the app and system actions. Demo dependencies
/// are injected only after an explicit in-app demo action.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let authentication: AuthenticationClient
    let profile: ProfileClient
    let deletion: AccountDeletionClient
    let friendship: FriendshipClient
    let availability: BackendAvailabilityAdapter
    let hosting: BackendHostingAdapter
    let scheduling: AutomaticSchedulingUseCase
    let pushEnvironment: String?
    private let schedulingDeviceWriter = SchedulingDeviceWriter()
    let deletionStore = KeychainDeletionStatusTokenStore().client()
    let handoff = SystemActionHandoffCoordinator()

    init(bundle: Bundle = .main) {

        pushEnvironment = try? SchedulingPushEnvironment.apiValue(bundle.object(forInfoDictionaryKey: "HIMATCH_APNS_ENVIRONMENT") as? String)

        do {
            let configuration = try AppConfiguration(bundle: bundle)
            let supabase = SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.supabasePublishableKey
            )
            authentication = SupabaseAuthenticationAdapter(supabase: supabase).client()
            profile = BackendProfileAdapter(baseURL: configuration.apiBaseURL).client()
            deletion = BackendAccountDeletionAdapter(baseURL: configuration.apiBaseURL).client()
            friendship = BackendFriendshipAdapter(baseURL: configuration.apiBaseURL).client()
            availability = BackendAvailabilityAdapter(baseURL: configuration.apiBaseURL)
            hosting = BackendHostingAdapter(baseURL: configuration.apiBaseURL)
            scheduling = AutomaticSchedulingUseCase(repository: BackendAutomaticSchedulingAdapter(baseURL: configuration.apiBaseURL).repository())
        } catch {
            let message = error.localizedDescription
            authentication = .unconfigured(message)
            profile = .unconfigured(message)
            deletion = .unconfigured(message)
            friendship = .unconfigured(message)
            availability = BackendAvailabilityAdapter(baseURL: URL(string: "https://invalid.local/")!)
            hosting = BackendHostingAdapter(baseURL: URL(string: "https://invalid.local/")!)
            scheduling = AutomaticSchedulingUseCase(repository: BackendAutomaticSchedulingAdapter(baseURL: URL(string: "https://invalid.local/")!).repository())
        }

    }

    lazy var systemActions: SystemActionService = {
        let authentication = authentication
        let profile = profile
        let friendship = friendship
        let availability = availability
        let hosting = hosting
        let deletionStore = deletionStore
        let directory = URL.applicationSupportDirectory.appending(path: "SystemActions", directoryHint: .isDirectory)
        return SystemActionService(dependencies: SystemActionDependencies(
            authenticatedOwner: {
                if try deletionStore.load() != nil || deletionStore.loadOperationID() != nil {
                    throw SystemActionAccessError.accountStopped
                }
                guard let session = try await authentication.restoreSession() else {
                    throw SystemActionAccessError.needsAuthentication
                }
                guard let ownProfile = try await profile.get(session.accessToken) else {
                    throw SystemActionAccessError.profileRequired
                }
                guard ownProfile.userID == session.userID else { throw SystemActionAccessError.accountChanged }
                return session.userID
            },
            businessClientForOwner: { owner in
                Self.productionBusiness(authentication: authentication, availability: availability, hosting: hosting, expectedUserID: owner, includeAvailabilitySnapshot: false, accessGate: {
                    if try deletionStore.load() != nil || deletionStore.loadOperationID() != nil {
                        throw SystemActionAccessError.accountStopped
                    }
                })
            },
            friendsForOwner: { owner in
                guard let session = try await authentication.restoreSession(), session.userID == owner else {
                    throw SystemActionAccessError.accountChanged
                }
                return try await friendship.load(session.accessToken).friends
            },
            protectedDataAvailable: { await MainActor.run { UIApplication.shared.isProtectedDataAvailable } },
            journal: SystemActionJournal(directory: directory).client,
            restoredOwnerID: { try await authentication.restoreSession()?.userID }
        ))
    }()

    var business: HimatchClient {
        Self.productionBusiness(authentication: authentication, availability: availability, hosting: hosting)
    }

    var schedulingEffects: AutomaticSchedulingEffects {
        let scheduling = scheduling
        let authentication = authentication
        let deletionStore = deletionStore
        let environment = pushEnvironment
        let deviceWriter = schedulingDeviceWriter
        let token: @Sendable (String) async throws -> String = { expectedOwner in
            guard try deletionStore.load() == nil, try deletionStore.loadOperationID() == nil,
                  let session = try await authentication.restoreSession(), session.userID == expectedOwner else {
                throw SchedulingFailure.unauthorized
            }
            return session.accessToken
        }
        let registerDevice: @Sendable (String, Bool, String) async throws -> Void = { deviceToken, enabled, owner in
            guard let environment else { throw SchedulingFailure.rejected }
            try await deviceWriter.write {
                let accessToken = try await token(owner)
                _ = try await scheduling.registerDevice(token: deviceToken, environment: environment, enabled: enabled, accessToken: accessToken)
            }
        }
        return .init(
            load: { owner in try await scheduling.load(token: token(owner)) },
            execute: { command, operationID, owner in
                try await scheduling.execute(command, operationID: operationID, token: token(owner))
            },
            requestNotifications: { owner in
                _ = try await token(owner)
                guard try await SchedulingPushAdapter.shared.requestPermission() else { return false }
                guard environment != nil else { throw SchedulingFailure.rejected }
                let deviceToken = try await SchedulingPushAdapter.shared.register()
                try await registerDevice(deviceToken, true, owner)
                return true
            },
            synchronizeDevice: { owner in
                guard environment != nil else { return }
                if !(await SchedulingPushAdapter.shared.enabled) {
                    // A new account must also reclaim a disabled token after an offline logout.
                    if let deviceToken = await SchedulingPushAdapter.shared.storedToken {
                        try await registerDevice(deviceToken, false, owner)
                    }
                    return
                }
                let allowed = await SchedulingPushAdapter.shared.allowed()
                if allowed {
                    let deviceToken = try await SchedulingPushAdapter.shared.register()
                    try await registerDevice(deviceToken, true, owner)
                } else if let deviceToken = await SchedulingPushAdapter.shared.storedToken {
                    try await registerDevice(deviceToken, false, owner)
                }
            },
            disableDevice: { owner in
                await SchedulingPushAdapter.shared.disableLocally()
                guard let deviceToken = await SchedulingPushAdapter.shared.storedToken, environment != nil else { return }
                try await registerDevice(deviceToken, false, owner)
            }
        )
    }

    func requestSystemActionHandoff(operationID: UUID) {
        handoff.request(operationID)
    }

    nonisolated static func productionBusiness(
        authentication: AuthenticationClient,
        availability: BackendAvailabilityAdapter,
        hosting: BackendHostingAdapter,
        expectedUserID: String? = nil,
        includeAvailabilitySnapshot: Bool = true,
        accessGate: @escaping @Sendable () throws -> Void = {}
    ) -> HimatchClient {
        var client = HimatchClient.productionPlaceholder
        client.loadAvailability = {
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            try accessGate()
            return try await availability.load(accessToken: session.accessToken)
        }
        client.addAvailability = { slot in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            try accessGate()
            return AppSnapshot.empty(availability: try await availability.put(slot, accessToken: session.accessToken))
        }
        client.removeAvailability = { id in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            return AppSnapshot.empty(availability: try await availability.delete(id: id, accessToken: session.accessToken))
        }
        client.subtractAvailability = { interval, operationID in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            try accessGate()
            return AppSnapshot.empty(availability: try await availability.subtract(interval, operationID: operationID, accessToken: session.accessToken))
        }
        client.loadHostings = {
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            return try await hosting.load(accessToken: session.accessToken)
        }
        client.createHosting = { draft in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            try accessGate()
            let created = try await hosting.create(draft, operationID: draft.operationID, accessToken: session.accessToken)
            let availabilitySlots = includeAvailabilitySnapshot ? try await availability.load(accessToken: session.accessToken) : []
            var snapshot = AppSnapshot.empty(availability: availabilitySlots)
            snapshot.hostings = created.isHostedByMe ? [created] : []
            snapshot.invitations = created.isHostedByMe ? [] : [created]
            return snapshot
        }
        client.respondInvitation = { id, status, intervals, operationID, version in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            let response = try await hosting.respond(id: id, status: status, intervals: intervals,
                                                    operationID: operationID, expectedVersion: version,
                                                    accessToken: session.accessToken)
            var snapshot = AppSnapshot.empty(availability: try await availability.load(accessToken: session.accessToken))
            snapshot.invitations = response.isHostedByMe ? [] : [response]
            snapshot.hostings = response.isHostedByMe ? [response] : []
            return snapshot
        }
        client.cancelHosting = { id, operationID, version in
            guard let session = try await authentication.restoreSession() else {
                throw AuthenticationFailure.unavailable("サインイン状態を確認できません。もう一度お試しください。")
            }
            if let expectedUserID, session.userID != expectedUserID {
                throw SystemActionAccessError.accountChanged
            }
            try accessGate()
            let cancelled = try await hosting.cancel(id: id, operationID: operationID, expectedVersion: version,
                                                     accessToken: session.accessToken)
            let slots = includeAvailabilitySnapshot ? try await availability.load(accessToken: session.accessToken) : []
            var snapshot = AppSnapshot.empty(availability: slots)
            snapshot.hostings = [cancelled]
            return snapshot
        }
        return client
    }
}
