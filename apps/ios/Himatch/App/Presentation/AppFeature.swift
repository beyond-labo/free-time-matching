import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    private enum CancelID: Hashable {
        case friendship
    }

    @ObservableState
    struct State: Equatable {
        enum Route: Equatable {
            case launching
            case onboarding
            case profile
            case main
            case deletionAccepted
        }

        enum Tab: Hashable {
            case home
            case friends
            case settings
        }

        var route: Route = .launching
        var selectedTab: Tab = .home
        var snapshot: AppSnapshot?
        var systemActionOperationID: UUID?
        var availabilityRevision = 0
        var hostingRevision = 0
        var authenticationSession: AuthenticationSession?
        var isDemo = false
        var isLoading = false
        var isAvailabilityLoading = false
        var availabilityLoadError = false
        var isFriendshipLoading = false
        var friendshipLoadError = false
        var alertMessage: String?

        var profileName = "ひまり"
        var profileIcon = PresetProfileIcon.sun.rawValue
        var profileValidationMessage: String?

        var homeTimeline = HomeTimelineFeature.State()
        var automaticScheduling = AutomaticSchedulingFeature.State()
        @Presents var availabilityEditor: AvailabilityEditorFeature.State?
        var calendarPresented = false
        var hostingLoadError = false

        @Presents var composer: InvitationComposerFeature.State?
        @Presents var reply: InvitationReplyFeature.State?
        var sentInvitation: Hosting?
        var firstMatchRecord = FirstMatchRecord()
        var participationBanner: ParticipationBanner?
        var shownParticipationKeys: Set<String> = []
        var hostingResponseOperationIDs: [String: UUID] = [:]
        var hostingCancelOperationIDs: [String: UUID] = [:]

        var inboxPresented = false
        var addFriendPresented = false
        var inviteCodeInput = ""
        var friendCandidate: FriendProfile?
        var friendshipOperationID: UUID?
        var friendshipOperationKey: String?
        var reportPresented = false
        var reportReason: ReportReason = .nuisanceInvitation
        var reportNote = ""
        var reportReceipt: String?
        var blockTarget: FriendProfile?
        var deleteConfirmationPresented = false
        var accountDeletionReceipt: AccountDeletionReceipt?
        var deletionOperationID: UUID?
        var deletionRecoveryMessage: String?

        var invitationNotifications = true
        var responseNotifications = true
        var planNotifications = true
        var reminderEnabled = false

        /// Device-local record key: the internal user ID, or `demo` for the DEBUG demo. Never a display name.
        var accountKey: String? {
            if isDemo { return FirstMatchLocalStore.demoAccountKey }
            return authenticationSession?.userID
        }

        mutating func operationID(forFriendshipKey key: String) -> UUID {
            if friendshipOperationKey == key, let friendshipOperationID {
                return friendshipOperationID
            }
            let operationID = UUID()
            friendshipOperationKey = key
            friendshipOperationID = operationID
            return operationID
        }

        mutating func clearFriendshipOperation() {
            friendshipOperationKey = nil
            friendshipOperationID = nil
        }
    }

    enum Action {
        case task
        case systemActionsForeground
        case systemActionAvailable(UUID)
        case systemActionDismissed
        case systemActionCompleted
        case snapshotLoaded(AppSnapshot)
        case sessionRestored(AuthenticationSession?)
        case sessionRestoreFailed(String)
        case pendingDeletionRestored(AccountDeletionReceipt)
        case deletionAttemptRestored(UUID, AuthenticationSession?)
        case authenticationStateChanged(AuthenticationStateChange)
        case authenticationInvalidated(String)
        case operationFailed(String)
        case dismissAlert

        case appleAuthorizationCompleted(AppleAuthorizationCredential)
        case appleAuthorizationFailed(String?)
        case authenticationSucceeded(AuthenticationSession)
        case profileLoaded(UserProfile?)
        case reloadAvailability
        case reloadHostings
        case availabilityLoaded([AvailabilitySlot], revision: Int, userID: String)
        case availabilityLoadFailed(String, revision: Int, userID: String)
        case profileLoadFailed(String)
#if DEBUG
        case startDemo(DemoSeed)
        case demoSnapshotLoaded(AppSnapshot)
        case demoFriendRequestTapped
        case demoAcceptanceTapped(UUID)
        case demoProposalTapped
        case demoPeerAcceptanceTapped(UUID)
#endif
        case profileNameChanged(String)
        case profileIconChanged(String)
        case saveProfileTapped
        case profileSaved(AppSnapshot)
        case profileSaveFailed(String)
        case selectTab(State.Tab)
        case logoutTapped
        case logoutCompleted

        case homeTimeline(HomeTimelineFeature.Action)
        case automaticScheduling(AutomaticSchedulingFeature.Action)
        case availabilityEditor(PresentationAction<AvailabilityEditorFeature.Action>)
        case removeAvailability(UUID)
        case quickSaveSucceeded(AppSnapshot, slotID: UUID)
        case quickSaveFailed(String)
        case availabilitySubtracted(AppSnapshot)
        case availabilityDeletionBlocked
        case hostingLoadCompleted([Hosting], [Hosting], revision: Int, userID: String)
        case hostingLoadFailed(String, revision: Int, userID: String)
        case showCalendar(Bool)
        case homeAppeared
        case homeRefreshed
        case registerAvailabilityTapped
        case primaryActionTapped
        case dismissGuide
        case inviteCodeShared
        case participationBannerDismissed

        case startInvitation(InvitationStart)
        case composer(PresentationAction<InvitationComposerFeature.Action>)
        case inviteFriendFromProfile(UUID)
        case hostingCreated(AppSnapshot, owner: String?)
        case hostingCreationFailed(String, owner: String?)
        case sentInvitationDismissed
        case inboxReplyTapped(UUID)
        case openReply(UUID)
        case reply(PresentationAction<InvitationReplyFeature.Action>)
        case responseFailed(String, owner: String?)
        case respondToInvitation(UUID, HostingInvitation.Status, [TimeIntervalRange])
        case hostingMutationCompleted(UUID, Bool, AppSnapshot, owner: String?)
        case cancelHosting(UUID)

        case showInbox(Bool)
        case showAddFriend(Bool)
        case inviteCodeChanged(String)
        case reloadFriendships
        case friendshipsLoaded(FriendshipSnapshot, userID: String)
        case friendshipLoadFailed(String, userID: String)
        case rotateInviteCode
        case resolveInviteCode
        case inviteCodeResolved(FriendProfile, userID: String)
        case sendFriendRequest
        case acceptRequest(UUID)
        case rejectRequest(UUID)
        case cancelRequest(UUID)
        case removeFriend(UUID)
        case friendshipMutationCompleted(FriendshipSnapshot, userID: String)
        case friendshipMutationFailed(String, reload: Bool, userID: String)
        case snapshotMutationCompleted(AppSnapshot)

        case showReport(Bool)
        case reportReasonChanged(ReportReason)
        case reportNoteChanged(String)
        case submitReportTapped
        case reportSubmitted(ReportReceipt)
        case setBlockTarget(FriendProfile?)
        case confirmBlock(UUID)

        case toggleInvitationNotifications
        case toggleResponseNotifications
        case togglePlanNotifications
        case toggleReminder
        case showDeleteConfirmation(Bool)
        case deleteAccountAuthorized(AppleAuthorizationCredential)
        case deletionSubmitted(AccountDeletionReceipt)
        case deletionSubmissionFailed(String)
    }

    @Dependency(\.himatchClient) var liveClient
#if DEBUG
    @Dependency(\.demoScenarioClient) var demoScenarioClient
#endif
    @Dependency(\.firstMatchLocalStore) var firstMatchLocalStore
    @Dependency(\.authenticationClient) var authenticationClient
    @Dependency(\.friendshipClient) var friendshipClient
    @Dependency(\.profileClient) var profileClient
    @Dependency(\.accountDeletionClient) var accountDeletionClient
    @Dependency(\.deletionStatusTokenStore) var deletionStatusTokenStore
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.uuid) var uuid
    @Dependency(\.continuousClock) var clock
    @Dependency(\.systemActionHandoffClient) var systemActionHandoffClient
    @Dependency(\.automaticSchedulingEffects) var schedulingEffects

    var body: some ReducerOf<Self> {
        Scope(state: \.homeTimeline, action: \.homeTimeline) {
            HomeTimelineFeature()
        }
        Scope(state: \.automaticScheduling, action: \.automaticScheduling) {
            AutomaticSchedulingFeature()
        }
        firstMatchCore
            .ifLet(\.$composer, action: \.composer) { InvitationComposerFeature() }
            .ifLet(\.$reply, action: \.reply) { InvitationReplyFeature() }
        Reduce<State, Action> { state, _ in
            guard state.route == .main else { return .none }
            evaluateFirstMatch(&state)
            return .none
        }
    }

    private var firstMatchCore: some ReducerOf<Self> {
        Reduce { state, action in
            let client = business(for: state)
            switch action {
            case .automaticScheduling(.delegate(.authenticationInvalidated)):
                return .send(.authenticationInvalidated("サインインし直してください。"))
            case .automaticScheduling(.delegate(.safetyChanged)):
                return .merge(.send(.reloadFriendships), .send(.reloadHostings))
            case .automaticScheduling:
                return .none
            case .systemActionsForeground:
                guard state.route == .main, !state.isDemo, let schedulingOwner = state.authenticationSession?.userID else { return .none }
                return .merge(
                    .send(.reloadAvailability), .send(.reloadHostings),
                    .send(.automaticScheduling(.activate(schedulingOwner))),
                    .run { [owner = state.authenticationSession?.userID] _ in
                        if let owner { try? await schedulingEffects.synchronizeDevice(owner) }
                    },
                    .run { send in
                        if let id = await systemActionHandoffClient.pendingOperationID() {
                            await send(.systemActionAvailable(id))
                        }
                    }
                )

            case let .systemActionAvailable(id):
                guard state.route == .main, !state.isDemo, state.systemActionOperationID == nil else { return .none }
                state.systemActionOperationID = id
                return .none

            case .systemActionDismissed:
                state.systemActionOperationID = nil
                return .none

            case .systemActionCompleted:
                state.systemActionOperationID = nil
                return .send(.systemActionsForeground)

            case .task:
                state.isLoading = true
                return .merge(
                    .run { send in
                        do {
                            if let pending = try deletionStatusTokenStore.load() {
                                do {
                                    let receipt = try await accountDeletionClient.status(pending)
                                    if receipt.status == .completed {
                                        try deletionStatusTokenStore.remove()
                                        try? deletionStatusTokenStore.removeOperationID()
                                    }
                                    await send(.pendingDeletionRestored(receipt))
                                } catch {
                                    await send(.pendingDeletionRestored(AccountDeletionReceipt(
                                        reference: pending.reference,
                                        status: .actionRequired,
                                        statusToken: pending.statusToken,
                                        message: "削除状況を確認できませんでした。通信環境を確認して再起動してください。"
                                    )))
                                }
                            } else if let operationID = try deletionStatusTokenStore.loadOperationID() {
                                let session = try? await authenticationClient.restoreSession()
                                await send(.deletionAttemptRestored(operationID, session))
                            } else {
                                await send(.sessionRestored(try await authenticationClient.restoreSession()))
                            }
                        } catch {
                            await send(.sessionRestoreFailed(error.localizedDescription))
                        }
                    },
                    .run { send in
                        for await change in authenticationClient.stateChanges() {
                            await send(.authenticationStateChanged(change))
                        }
                    }
                )

            case let .pendingDeletionRestored(receipt):
                state.accountDeletionReceipt = receipt
                state.authenticationSession = nil
                state.snapshot = .empty()
                switch receipt.status {
                case .accepted:
                    state.snapshot?.deletionStatus = .accepted(reference: receipt.reference)
                case .processing:
                    state.snapshot?.deletionStatus = .processing(reference: receipt.reference)
                case .completed:
                    state.snapshot?.deletionStatus = .completed
                case .actionRequired:
                    state.snapshot?.deletionStatus = .actionRequired(
                        reference: receipt.reference,
                        message: receipt.message ?? "追加対応が必要です。"
                    )
                }
                state.isLoading = false
                state.route = .deletionAccepted
                return .none

            case let .deletionAttemptRestored(operationID, session):
                state.deletionOperationID = operationID
                state.authenticationSession = session
                state.snapshot = .empty()
                state.deletionRecoveryMessage = session == nil
                    ? "削除要求の結果を確認できません。操作ID \(operationID.uuidString) を控えてサポートへお問い合わせください。"
                    : "前回の削除要求は結果が不明です。Appleで再認証すると同じ操作IDで安全に再送できます。"
                state.isLoading = false
                state.route = .deletionAccepted
                return .none

            case let .snapshotLoaded(snapshot):
                state.snapshot = snapshot
                if state.authenticationSession == nil || state.isDemo {
                    state.profileName = snapshot.profileName
                    state.profileIcon = snapshot.profileIcon
                } else {
                    let profileName = state.profileName
                    let profileIcon = state.profileIcon
                    state.snapshot?.profileName = profileName
                    state.snapshot?.profileIcon = profileIcon
                }
                revalidateSelection(&state)
                return .none

            case let .sessionRestored(session):
                state.authenticationSession = session
                guard let session else {
                    state.route = .onboarding
                    state.isLoading = false
                    return .run { send in await send(.snapshotLoaded(client.load())) }
                }
                return loadProfile(session: session)

            case let .sessionRestoreFailed(message):
                state.route = .onboarding
                state.isLoading = false
                state.alertMessage = message
                return .none

            case let .authenticationStateChanged(change):
                switch change {
                case let .authenticated(session):
                    // The launch effect must resolve a locally stored deletion receipt
                    // before an SDK auth event can restore access to authenticated UI.
                    // A concurrent initial-session event is intentionally ignored here;
                    // sessionRestored performs the same profile load once that check ends.
                    guard state.route != .launching else { return .none }
                    if state.route == .deletionAccepted, state.accountDeletionReceipt != nil {
                        return .none
                    }
                    let previousOwner = state.authenticationSession?.userID
                    let ownerChanged = previousOwner != nil && previousOwner != session.userID
                    if ownerChanged {
                        resetAccountScopedState(&state)
                        state.systemActionOperationID = nil
                        let revision = state.automaticScheduling.revision + 1
                        state.automaticScheduling = .init()
                        state.automaticScheduling.revision = revision
                        state.snapshot = nil
                    }
                    state.authenticationSession = session
                    guard state.route != .deletionAccepted else { return .none }
                    return .merge(
                        .cancel(id: CancelID.friendship),
                        loadProfile(session: session),
                        .run { _ in
                            if ownerChanged, let previousOwner { await systemActionHandoffClient.invalidate(previousOwner) }
                        }
                    )
                case .signedOut:
                    guard state.route != .launching else { return .none }
                    let previousOwner = state.authenticationSession?.userID
                    resetAccountScopedState(&state)
                    state.systemActionOperationID = nil
                    state.authenticationSession = nil
                    let revision = state.automaticScheduling.revision + 1
                    state.automaticScheduling = .init()
                    state.automaticScheduling.revision = revision
                    state.isAvailabilityLoading = false
                    state.isFriendshipLoading = false
                    guard state.route != .deletionAccepted else { return .none }
                    state.snapshot = nil
                    state.route = .onboarding
                    state.isLoading = false
                    return .merge(.cancel(id: CancelID.friendship), .run { _ in
                        if let previousOwner { await systemActionHandoffClient.invalidate(previousOwner) }
                    })
                }

            case let .authenticationInvalidated(message):
                let previousOwner = state.authenticationSession?.userID
                resetAccountScopedState(&state)
                state.systemActionOperationID = nil
                state.authenticationSession = nil
                let revision = state.automaticScheduling.revision + 1
                state.automaticScheduling = .init()
                state.automaticScheduling.revision = revision
                state.isAvailabilityLoading = false
                state.isFriendshipLoading = false
                state.snapshot = nil
                state.isDemo = false
                state.isLoading = false
                state.route = .onboarding
                state.alertMessage = message
                return .merge(.cancel(id: CancelID.friendship), .run { _ in
                    if let previousOwner { await systemActionHandoffClient.invalidate(previousOwner) }
                })

            case let .operationFailed(message):
                state.isLoading = false
                state.alertMessage = message
                return .none

            case .dismissAlert:
                state.alertMessage = nil
                return .none

            case let .appleAuthorizationCompleted(credential):
                state.isLoading = true
                return .run { send in
                    do { await send(.authenticationSucceeded(try await authenticationClient.signInWithApple(credential))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .appleAuthorizationFailed(message):
                if let message { state.alertMessage = message }
                return .none

            case let .authenticationSucceeded(session):
                state.authenticationSession = session
                return .merge(
                    .cancel(id: CancelID.friendship),
                    loadProfile(session: session)
                )

            case let .profileLoaded(profile):
                state.isLoading = false
                guard let profile else {
                    state.route = .profile
                    return .none
                }
                state.profileName = profile.nickname
                state.profileIcon = profile.presetIcon.rawValue
                if state.snapshot == nil { state.snapshot = .empty() }
                state.snapshot?.profileName = profile.nickname
                state.snapshot?.profileIcon = profile.presetIcon.rawValue
                state.route = .main
                guard !state.isDemo, state.authenticationSession != nil else { return .none }
                return .merge(.send(.reloadFriendships), .send(.reloadAvailability), .send(.reloadHostings),
                              .send(.automaticScheduling(.activate(state.authenticationSession!.userID))))

            case .reloadAvailability:
                guard !state.isDemo, let session = state.authenticationSession else { return .none }
                state.isAvailabilityLoading = true
                state.availabilityLoadError = false
                let revision = state.availabilityRevision
                let userID = session.userID
                return .run { [client] send in
                    do {
                        await send(.availabilityLoaded(try await client.loadAvailability(), revision: revision, userID: userID))
                    } catch {
                        await send(.availabilityLoadFailed(error.localizedDescription, revision: revision, userID: userID))
                    }
                }

            case .reloadHostings:
                guard !state.isDemo, let session = state.authenticationSession else { return .none }
                let revision = state.hostingRevision
                let userID = session.userID
                return .run { [client] send in
                    do {
                        let hosting = try await client.loadHostings()
                        await send(.hostingLoadCompleted(hosting.hostings, hosting.invitations, revision: revision, userID: userID))
                    } catch {
                        await send(.hostingLoadFailed(error.localizedDescription, revision: revision, userID: userID))
                    }
                }

            case let .availabilityLoaded(availability, revision, userID):
                guard revision == state.availabilityRevision, state.authenticationSession?.userID == userID else { return .none }
                state.isAvailabilityLoading = false
                state.availabilityLoadError = false
                if state.snapshot == nil { state.snapshot = .empty() }
                state.snapshot?.availability = availability
                revalidateSelection(&state)
                return .none

            case let .availabilityLoadFailed(message, revision, userID):
                guard revision == state.availabilityRevision, state.authenticationSession?.userID == userID else { return .none }
                state.isAvailabilityLoading = false
                state.availabilityLoadError = true
                state.alertMessage = message
                return .none

            case let .profileLoadFailed(message):
                state.isLoading = false
                state.alertMessage = message
                state.route = .profile
                return .none

#if DEBUG
            case let .startDemo(seed):
                state.isDemo = true
                // Each demo starts fresh, including the device-local guide record.
                firstMatchLocalStore.remove(FirstMatchLocalStore.demoAccountKey)
                resetAccountScopedState(&state)
                state.route = .profile
                state.isLoading = true
                state.profileValidationMessage = nil
                return .run { [demoScenarioClient] send in
                    await send(.demoSnapshotLoaded(await demoScenarioClient.reset(seed)))
                }

            case let .demoSnapshotLoaded(snapshot):
                state.isLoading = false
                state.snapshot = snapshot
                state.profileName = snapshot.profileName
                state.profileIcon = snapshot.profileIcon
                return .none

            case .demoFriendRequestTapped:
                guard state.isDemo else { return .none }
                return .run { [demoScenarioClient] send in
                    await send(.snapshotMutationCompleted(await demoScenarioClient.simulateFriendRequest()))
                }

            case let .demoAcceptanceTapped(hostingID):
                guard state.isDemo else { return .none }
                return .run { [demoScenarioClient] send in
                    await send(.snapshotMutationCompleted(await demoScenarioClient.simulateAcceptance(hostingID)))
                }

            case .demoProposalTapped:
                guard state.isDemo else { return .none }
                return .run { [demoScenarioClient] send in
                    _ = await demoScenarioClient.simulateProposal()
                    await send(.automaticScheduling(.refresh))
                }

            case let .demoPeerAcceptanceTapped(proposalID):
                guard state.isDemo else { return .none }
                return .run { [demoScenarioClient] send in
                    _ = await demoScenarioClient.simulatePeerAcceptance(proposalID)
                    await send(.automaticScheduling(.refresh))
                }
#endif

            case let .profileNameChanged(value):
                state.profileName = value
                return .none

            case let .profileIconChanged(value):
                state.profileIcon = value
                return .none

            case .saveProfileTapped:
                let normalized: String
                let icon: PresetProfileIcon
                do {
                    normalized = try ProfilePolicy.validatedNickname(state.profileName)
                    icon = try ProfilePolicy.presetIcon(state.profileIcon)
                    state.profileValidationMessage = nil
                } catch {
                    state.profileValidationMessage = error.localizedDescription
                    return .none
                }
                state.isLoading = true
                if state.isDemo {
                    return .run { send in
                        do { await send(.profileSaved(try await client.saveProfile(normalized, icon.rawValue))) }
                        catch { await send(.operationFailed(error.localizedDescription)) }
                    }
                }
                guard let session = state.authenticationSession else {
                    state.isLoading = false
                    state.alertMessage = "セッションを確認できません。Appleでサインインし直してください。"
                    state.route = .onboarding
                    return .none
                }
                let currentSnapshot = state.snapshot ?? .empty()
                return .run { send in
                    do {
                        let profile = try await profileClient.put(normalized, icon, session.accessToken)
                        var snapshot = currentSnapshot
                        snapshot.profileName = profile.nickname
                        snapshot.profileIcon = profile.presetIcon.rawValue
                        await send(.profileSaved(snapshot))
                    } catch {
                        if let message = authenticationRejectionMessage(error) {
                            try? await authenticationClient.signOut()
                            await send(.authenticationInvalidated(message))
                        } else if case let BackendClientError.response(status, message) = error, status == 400 {
                            await send(.profileSaveFailed(message ?? "プロフィールを保存できませんでした。"))
                        } else {
                            await send(.profileLoadFailed(error.localizedDescription))
                        }
                    }
                }

            case let .profileSaved(snapshot):
                state.snapshot = snapshot
                state.profileName = snapshot.profileName
                state.profileIcon = snapshot.profileIcon
                state.profileValidationMessage = nil
                state.isLoading = false
                state.route = .main
                if state.isDemo {
                    // The demo owner is routed to the prototype's automatic proposals by composition.
                    return .send(.automaticScheduling(.activate(FirstMatchLocalStore.demoAccountKey)))
                }
                return state.authenticationSession == nil ? .none : .send(.reloadFriendships)

            case let .profileSaveFailed(message):
                state.isLoading = false
                state.profileValidationMessage = message
                state.route = .profile
                return .none

            case let .selectTab(tab):
                state.selectedTab = tab
                return .none

            case .logoutTapped:
                if state.isDemo {
                    return .send(.logoutCompleted)
                }
                state.isLoading = true
                return .merge(
                    .cancel(id: CancelID.friendship),
                    .run { [owner = state.authenticationSession?.userID] send in
                        do {
                            if let owner { await systemActionHandoffClient.invalidate(owner) }
                            var deviceDisableFailed = false
                            if let owner {
                                do { try await schedulingEffects.disableDevice(owner) }
                                catch { deviceDisableFailed = true }
                            }
                            try await authenticationClient.signOut()
                            await send(.logoutCompleted)
                            if deviceDisableFailed { await send(.operationFailed("ログアウトしました。端末の通知停止は確認できませんでした。通知本文に相手名や暇時間は含まれません。")) }
                        } catch {
                            await send(.operationFailed(error.localizedDescription))
                        }
                    }
                )

            case .logoutCompleted:
                let schedulingRevision = state.automaticScheduling.revision + 1
                state = State()
                state.automaticScheduling.revision = schedulingRevision
                state.route = .onboarding
                state.isLoading = false
                return .cancel(id: CancelID.friendship)

            case let .homeTimeline(.delegate(.startAvailability(anchor))):
                guard let editor = AvailabilityEditorFeature.State(
                    anchor: anchor,
                    now: now,
                    calendar: calendar,
                    existing: state.snapshot?.availability ?? [],
                    slotID: uuid()
                ) else {
                    state.alertMessage = "この時間からは登録できません。今後14日以内の時間を選んでください。"
                    return .none
                }
                state.availabilityEditor = editor
                return .none

            case let .homeTimeline(.delegate(.removeAvailability(id))):
                return .send(.removeAvailability(id))

            case let .homeTimeline(.delegate(.startHosting(range))):
                return .send(.startInvitation(.range(range)))

            case let .homeTimeline(.delegate(.subtractAvailability(range, operationID))):
                let interval = TimeIntervalRange(start: range.start, end: range.end)
                if hasActiveHosting(overlapping: interval, in: state.snapshot?.hostings ?? []) {
                    state.alertMessage = "お誘い中の時間は削除できません。ホームでお誘いを取り消してから、もう一度削除してください。"
                    return .send(.showInbox(true))
                }
                state.homeTimeline.selection?.isSaving = true
                return .run { send in
                    do { await send(.availabilitySubtracted(try await client.subtractAvailability(interval, operationID))) }
                    catch let error as BackendClientError {
                        if case .response(409, _) = error { await send(.availabilityDeletionBlocked) }
                        else { await send(.quickSaveFailed(error.localizedDescription)) }
                    } catch { await send(.quickSaveFailed(error.localizedDescription)) }
                }

            case let .homeTimeline(.delegate(.quickSave(range, operationID))):
                guard let selection = state.homeTimeline.selection,
                      selection.range == range,
                      !selection.isSaving
                else { return .none }
                // Re-validate right before saving: the clock or the own slots may have changed.
                if let issue = availabilityIssue(range, existing: state.snapshot?.availability ?? []) {
                    state.homeTimeline.selection?.issue = issue
                    return .none
                }
                let slotID = operationID
                let overlapping = InvitationComposerFeature.State.connectedAvailability(range, existing: state.snapshot?.availability ?? [])
                if let first = overlapping.first,
                   overlapping.contains(where: { $0.category != first.category || $0.visibility != first.visibility }) {
                    state.availabilityEditor = AvailabilityEditorFeature.State(
                        range: range, now: now, calendar: calendar,
                        existing: state.snapshot?.availability ?? [], slotID: uuid()
                    )
                    return .none
                }
                let slot = AvailabilitySlot(
                    id: slotID,
                    interval: TimeIntervalRange(id: slotID, start: range.start, end: range.end),
                    category: overlapping.first?.category,
                    visibility: overlapping.first?.visibility ?? .privateUntilAccepted
                )
                state.homeTimeline.selection?.isSaving = true
                state.homeTimeline.selection?.saveError = nil
                return .run { send in
                    do {
                        await send(.quickSaveSucceeded(try await client.addAvailability(slot), slotID: slotID))
                    } catch let error as AvailabilityValidationError {
                        await send(.quickSaveFailed(error.message))
                    } catch {
                        await send(.quickSaveFailed(error.localizedDescription))
                    }
                }

            case let .homeTimeline(.delegate(.adjustSelection(range))):
                state.availabilityEditor = AvailabilityEditorFeature.State(
                    range: range,
                    now: now,
                    calendar: calendar,
                    existing: state.snapshot?.availability ?? [],
                    slotID: uuid()
                )
                return .none

            case .homeTimeline(.delegate):
                return .none

            case .homeTimeline:
                revalidateSelection(&state)
                return .none

            case let .quickSaveSucceeded(snapshot, slotID):
                state.availabilityRevision += 1
                state.isAvailabilityLoading = false
                let savedRange = state.homeTimeline.selection?.range
                applyBusinessSnapshot(snapshot, to: &state)
                state.homeTimeline.selection = nil
                let actualSlotID = snapshot.availability.first(where: {
                    guard let savedRange else { return false }
                    return $0.interval.start <= savedRange.start && $0.interval.end >= savedRange.end
                })?.id ?? slotID
                state.homeTimeline.lastSavedItem = .availability(actualSlotID)
                state.homeTimeline.quickSaveSuccessCount += 1
                return refreshScheduling(state)

            case let .quickSaveFailed(message):
                state.homeTimeline.selection?.isSaving = false
                state.homeTimeline.selection?.saveError = message
                return .none

            case let .availabilitySubtracted(snapshot):
                state.availabilityRevision += 1
                applyBusinessSnapshot(snapshot, to: &state)
                state.homeTimeline.selection = nil
                return refreshScheduling(state)

            case .availabilityDeletionBlocked:
                state.isLoading = false
                state.homeTimeline.selection?.isSaving = false
                state.alertMessage = "お誘い中の時間は削除できません。ホームでお誘いを取り消してから、もう一度削除してください。"
                return .send(.showInbox(true))

            case let .availabilityEditor(.presented(.delegate(.saved(snapshot)))):
                state.availabilityRevision += 1
                state.isAvailabilityLoading = false
                let savedStart = state.availabilityEditor?.start
                applyBusinessSnapshot(snapshot, to: &state)
                state.availabilityEditor = nil
                state.homeTimeline.selection = nil
                if let savedStart {
                    state.homeTimeline.focus(on: savedStart, item: nil, now: now, calendar: calendar)
                }
                return refreshScheduling(state)

            case let .availabilityEditor(.presented(.delegate(.showExistingSlot(id)))):
                state.availabilityEditor = nil
                if let slot = state.snapshot?.availability.first(where: { $0.id == id }) {
                    state.homeTimeline.focus(
                        on: slot.interval.start,
                        item: .availability(id),
                        now: now,
                        calendar: calendar
                    )
                }
                return .none

            case .availabilityEditor:
                return .none

            case let .showCalendar(presented):
                state.calendarPresented = presented
                return .none

            case .homeAppeared:
                loadFirstMatchRecord(&state)
                return state.isDemo || state.authenticationSession == nil ? .none : .send(.reloadHostings)

            case .homeRefreshed:
                if state.isDemo {
                    return .merge(
                        .run { [client] send in await send(.snapshotMutationCompleted(client.load())) },
                        refreshScheduling(state)
                    )
                }
                guard state.authenticationSession != nil else { return .none }
                return .merge(.send(.reloadFriendships), .send(.reloadAvailability), .send(.reloadHostings), refreshScheduling(state))

            case .registerAvailabilityTapped:
                state.calendarPresented = true
                return .send(.homeTimeline(.newAvailabilityTapped))

            case .primaryActionTapped:
                if state.snapshot?.friends.isEmpty ?? true { return .send(.showAddFriend(true)) }
                return .send(.registerAvailabilityTapped)

            case .dismissGuide:
                state.firstMatchRecord.guide = .dismissed
                saveFirstMatchRecord(state)
                return .none

            case .inviteCodeShared:
                state.firstMatchRecord.inviteCodeShared = true
                saveFirstMatchRecord(state)
                return .none

            case .participationBannerDismissed:
                state.participationBanner = nil
                return .none

            case let .removeAvailability(id):
                if let slot = state.snapshot?.availability.first(where: { $0.id == id }),
                   hasActiveHosting(overlapping: slot.interval, in: state.snapshot?.hostings ?? []) {
                    state.alertMessage = "お誘い中の時間は削除できません。ホームでお誘いを取り消してから、もう一度削除してください。"
                    return .send(.showInbox(true))
                }
                state.isLoading = true
                return .run { send in
                    do {
                        await send(.snapshotMutationCompleted(try await client.removeAvailability(id)))
                    } catch let error as BackendClientError {
                        if case .response(409, _) = error { await send(.availabilityDeletionBlocked) }
                        else { await send(.operationFailed(error.localizedDescription)) }
                    } catch {
                        await send(.operationFailed(error.localizedDescription))
                    }
                }

            case let .startInvitation(start):
                guard let snapshot = state.snapshot else { return .none }
                if snapshot.friends.isEmpty { return .send(.showAddFriend(true)) }
                loadFirstMatchRecord(&state)
                let openRanges = snapshot.hostings.filter { $0.isHostedByMe && $0.status == .recruiting }.map(\.candidateRange)
                state.composer = InvitationComposerFeature.State(
                    start: start,
                    friends: snapshot.friends,
                    availability: snapshot.availability,
                    candidates: TimeCandidatePolicy.candidates(
                        now: now, calendar: calendar, availability: snapshot.availability, activeHostingRanges: openRanges
                    ),
                    lastMeeting: state.firstMatchRecord.lastMeeting,
                    now: now,
                    operationID: uuid()
                )
                state.selectedTab = .home
                return .none

            case let .inviteFriendFromProfile(id):
                return .send(.startInvitation(.friend(id)))

            case let .composer(.presented(.delegate(.submit(draft)))):
                return .run { [owner = state.accountKey] send in
                    do { await send(.hostingCreated(try await client.createHosting(draft), owner: owner)) }
                    catch { await send(.hostingCreationFailed(error.localizedDescription, owner: owner)) }
                }

            case .composer(.presented(.delegate(.close))):
                guard state.composer?.isSubmitting != true else { return .none }
                state.composer = nil
                return .none

            case .composer:
                return .none

            case let .hostingCreated(snapshot, owner):
                // A result that arrives after an account switch belongs to the previous account.
                guard owner == state.accountKey else { return .none }
                state.hostingRevision += 1
                applyBusinessSnapshot(snapshot, to: &state)
                if let created = snapshot.hostings.first {
                    state.snapshot?.hostings.removeAll { $0.id == created.id }
                    state.snapshot?.hostings.append(created)
                    state.sentInvitation = created
                }
                if let composer = state.composer, let mode = composer.mode {
                    state.firstMatchRecord.lastMeeting = LastMeeting(mode: mode, area: mode == .offline ? composer.area : nil)
                    saveFirstMatchRecord(state)
                }
                state.composer = nil
                state.homeTimeline.selection = nil
                state.calendarPresented = false
                return .none

            case let .hostingCreationFailed(message, owner):
                guard owner == state.accountKey else { return .none }
                guard state.composer != nil else {
                    state.alertMessage = "お誘いを送れませんでした。\n\(message)"
                    return .none
                }
                return .send(.composer(.presented(.submissionFailed("お誘いを送れませんでした。入力内容はそのままです。\n\(message)"))))

            case .sentInvitationDismissed:
                state.sentInvitation = nil
                return .none

            case let .inboxReplyTapped(id):
                // Close お知らせ first; the reply sheet is presented from Home.
                state.inboxPresented = false
                return .run { [clock] send in
                    try await clock.sleep(for: .milliseconds(450))
                    await send(.openReply(id))
                }

            case let .openReply(id):
                guard let invitation = state.snapshot?.invitations.first(where: { $0.id == id }) else { return .none }
                state.reply = InvitationReplyFeature.State(invitation: invitation, now: now)
                return .none

            case let .reply(.presented(.delegate(.respond(status, intervals)))):
                guard let id = state.reply?.id else { return .none }
                return .send(.respondToInvitation(id, status, intervals))

            case .reply(.presented(.delegate(.close))):
                state.reply = nil
                return .none

            case .reply:
                return .none

            case let .responseFailed(message, owner):
                guard owner == state.accountKey else { return .none }
                state.isLoading = false
                guard state.reply != nil else {
                    state.alertMessage = message
                    return .none
                }
                return .send(.reply(.presented(.submissionFailed("返事を送れませんでした。選んだ時間はそのままです。\n\(message)"))))

            case let .respondToInvitation(id, status, intervals):
                guard let invitation = state.snapshot?.invitations.first(where: { $0.id == id }),
                      let version = invitation.myInvitation?.version else { return .none }
                let responseKey = "\(id.uuidString)|\(version)|\(status.rawValue)|" + intervals.map { "\($0.start.timeIntervalSince1970):\($0.end.timeIntervalSince1970)" }.joined(separator: ",")
                let operationID = state.hostingResponseOperationIDs[responseKey] ?? uuid()
                state.hostingResponseOperationIDs[responseKey] = operationID
                state.isLoading = true
                return .run { [owner = state.accountKey] send in
                    do { await send(.hostingMutationCompleted(id, true, try await client.respondInvitation(id, status, intervals, operationID, version), owner: owner)) }
                    catch { await send(.responseFailed(error.localizedDescription, owner: owner)) }
                }

            case let .cancelHosting(id):
                guard let hosting = state.snapshot?.hostings.first(where: { $0.id == id }) else { return .none }
                let cancelKey = "\(id.uuidString)|\(hosting.version)"
                let operationID = state.hostingCancelOperationIDs[cancelKey] ?? uuid()
                state.hostingCancelOperationIDs[cancelKey] = operationID
                state.isLoading = true
                return .run { [owner = state.accountKey] send in
                    do { await send(.hostingMutationCompleted(id, false, try await client.cancelHosting(id, operationID, hosting.version), owner: owner)) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .hostingMutationCompleted(id, isResponse, snapshot, owner):
                guard owner == state.accountKey else { return .none }
                state.isLoading = false
                state.hostingRevision += 1
                if state.isDemo {
                    // The prototype returns the whole projection rather than the single updated item.
                    state.snapshot = snapshot
                } else if let updated = snapshot.hostings.first ?? snapshot.invitations.first {
                    if updated.isHostedByMe {
                        state.snapshot?.hostings.removeAll { $0.id == id }
                        state.snapshot?.hostings.append(updated)
                    } else {
                        state.snapshot?.invitations.removeAll { $0.id == id }
                        state.snapshot?.invitations.append(updated)
                    }
                }
                if isResponse {
                    state.hostingResponseOperationIDs = state.hostingResponseOperationIDs.filter { !$0.key.hasPrefix("\(id.uuidString)|") }
                } else {
                    state.hostingCancelOperationIDs = state.hostingCancelOperationIDs.filter { !$0.key.hasPrefix("\(id.uuidString)|") }
                }
                if isResponse { state.reply = nil }
                return .none

            case let .showInbox(presented):
                state.inboxPresented = presented
                if presented, let hostings = state.snapshot?.hostings {
                    // Opening お知らせ marks the current 参加OK as seen (8.1).
                    state.firstMatchRecord.seenParticipationKeys = ParticipationNoticeDetector.activeKeys(hostings: hostings)
                    saveFirstMatchRecord(state)
                }
                guard presented, !state.isDemo, let session = state.authenticationSession else { return .none }
                let revision = state.hostingRevision
                let userID = session.userID
                return .merge(refreshScheduling(state), .run { [client] send in
                    do {
                        let hosting = try await client.loadHostings()
                        await send(.hostingLoadCompleted(hosting.hostings, hosting.invitations, revision: revision, userID: userID))
                    } catch { await send(.hostingLoadFailed(error.localizedDescription, revision: revision, userID: userID)) }
                })

            case let .hostingLoadCompleted(hostings, invitations, revision, userID):
                guard revision == state.hostingRevision, state.authenticationSession?.userID == userID else { return .none }
                state.snapshot?.hostings = hostings
                state.snapshot?.invitations = invitations
                state.hostingLoadError = false
                return .none

            case let .hostingLoadFailed(_, revision, userID):
                guard revision == state.hostingRevision, state.authenticationSession?.userID == userID else { return .none }
                state.hostingLoadError = true
                return .none

            case let .showAddFriend(presented):
                state.addFriendPresented = presented
                if !presented {
                    state.friendCandidate = nil
                    state.inviteCodeInput = ""
                }
                return .none

            case let .inviteCodeChanged(value):
                state.inviteCodeInput = value
                state.friendCandidate = nil
                return .none

            case .reloadFriendships:
                guard !state.isDemo, let session = state.authenticationSession else { return .none }
                state.isFriendshipLoading = true
                state.friendshipLoadError = false
                return .run { send in
                    do {
                        await send(.friendshipsLoaded(
                            try await friendshipClient.load(session.accessToken),
                            userID: session.userID
                        ))
                    } catch {
                        if let message = authenticationRejectionMessage(error) {
                            try? await authenticationClient.signOut()
                            await send(.authenticationInvalidated(message))
                        } else {
                            await send(.friendshipLoadFailed(error.localizedDescription, userID: session.userID))
                        }
                    }
                }
                .cancellable(id: CancelID.friendship, cancelInFlight: true)

            case let .friendshipsLoaded(friendship, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                if state.snapshot == nil { state.snapshot = .empty() }
                state.snapshot?.apply(friendship)
                state.isFriendshipLoading = false
                state.friendshipLoadError = false
                return .none

            case let .friendshipLoadFailed(message, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                state.isFriendshipLoading = false
                state.friendshipLoadError = true
                state.alertMessage = message
                return .none

            case .rotateInviteCode:
                guard !state.isDemo, let session = state.authenticationSession else { return .none }
                state.isLoading = true
                return .run { send in
                    do {
                        await send(.friendshipMutationCompleted(
                            try await friendshipClient.rotateCode(session.accessToken),
                            userID: session.userID
                        ))
                    } catch {
                        if let message = authenticationRejectionMessage(error) {
                            try? await authenticationClient.signOut()
                            await send(.authenticationInvalidated(message))
                        } else {
                            await send(.friendshipMutationFailed(
                                error.localizedDescription,
                                reload: false,
                                userID: session.userID
                            ))
                        }
                    }
                }
                .cancellable(id: CancelID.friendship, cancelInFlight: true)

            case .resolveInviteCode:
                guard let session = state.authenticationSession, !state.isDemo else {
                    state.alertMessage = "DEBUGデモでは共有済みの友達データを利用してください。"
                    return .none
                }
                let code = state.inviteCodeInput
                state.isLoading = true
                return .run { send in
                    do {
                        await send(.inviteCodeResolved(
                            try await friendshipClient.resolveCode(code, session.accessToken),
                            userID: session.userID
                        ))
                    } catch {
                        if let message = authenticationRejectionMessage(error) {
                            try? await authenticationClient.signOut()
                            await send(.authenticationInvalidated(message))
                        } else {
                            await send(.friendshipMutationFailed(
                                error.localizedDescription,
                                reload: false,
                                userID: session.userID
                            ))
                        }
                    }
                }
                .cancellable(id: CancelID.friendship, cancelInFlight: true)

            case let .inviteCodeResolved(friend, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                state.friendCandidate = friend
                state.isLoading = false
                return .none

            case .sendFriendRequest:
                guard state.friendCandidate != nil,
                      let session = state.authenticationSession,
                      !state.isDemo
                else { return .none }
                let code = state.inviteCodeInput
                let operationID = state.operationID(forFriendshipKey: "send:\(code)")
                state.isLoading = true
                return .run { send in
                    do {
                        await send(.friendshipMutationCompleted(
                            try await friendshipClient.sendRequest(code, operationID, session.accessToken),
                            userID: session.userID
                        ))
                    } catch let error as BackendClientError {
                        if let message = authenticationRejectionMessage(error) {
                            try? await authenticationClient.signOut()
                            await send(.authenticationInvalidated(message))
                        } else {
                            await send(.friendshipMutationFailed(
                                error.localizedDescription,
                                reload: isFriendshipConflict(error),
                                userID: session.userID
                            ))
                        }
                    } catch {
                        await send(.friendshipMutationFailed(
                            error.localizedDescription,
                            reload: false,
                            userID: session.userID
                        ))
                    }
                }
                .cancellable(id: CancelID.friendship, cancelInFlight: true)

            case let .acceptRequest(id):
                if state.isDemo {
                    return .run { send in await send(.snapshotMutationCompleted(client.acceptRequest(id))) }
                }
                guard let request = state.snapshot?.requests.first(where: { $0.id == id }),
                      let session = state.authenticationSession
                else { return .none }
                state.isLoading = true
                let operationID = state.operationID(
                    forFriendshipKey: "accept:\(request.id.uuidString):\(request.version)"
                )
                return friendshipTransitionEffect(
                    request,
                    .accept,
                    operationID,
                    session.accessToken,
                    session.userID
                )

            case let .rejectRequest(id):
                guard let request = state.snapshot?.requests.first(where: { $0.id == id }),
                      let session = state.authenticationSession,
                      !state.isDemo
                else { return .none }
                state.isLoading = true
                let operationID = state.operationID(
                    forFriendshipKey: "reject:\(request.id.uuidString):\(request.version)"
                )
                return friendshipTransitionEffect(
                    request,
                    .reject,
                    operationID,
                    session.accessToken,
                    session.userID
                )

            case let .cancelRequest(id):
                guard let request = state.snapshot?.requests.first(where: { $0.id == id }),
                      let session = state.authenticationSession,
                      !state.isDemo
                else { return .none }
                state.isLoading = true
                let operationID = state.operationID(
                    forFriendshipKey: "cancel:\(request.id.uuidString):\(request.version)"
                )
                return friendshipTransitionEffect(
                    request,
                    .cancel,
                    operationID,
                    session.accessToken,
                    session.userID
                )

            case let .removeFriend(id):
                if state.isDemo {
                    return .run { send in await send(.snapshotMutationCompleted(client.removeFriend(id))) }
                }
                guard let friend = state.snapshot?.friends.first(where: { $0.id == id }),
                      let version = friend.relationshipVersion,
                      let session = state.authenticationSession
                else { return .none }
                let operationID = state.operationID(
                    forFriendshipKey: "remove:\(id.uuidString):\(version)"
                )
                state.isLoading = true
                return .run { send in
                    do {
                        await send(.friendshipMutationCompleted(
                            try await friendshipClient.removeFriend(id, version, operationID, session.accessToken),
                            userID: session.userID
                        ))
                    } catch let error as BackendClientError {
                        if let message = authenticationRejectionMessage(error) {
                            try? await authenticationClient.signOut()
                            await send(.authenticationInvalidated(message))
                        } else {
                            await send(.friendshipMutationFailed(
                                error.localizedDescription,
                                reload: isFriendshipConflict(error),
                                userID: session.userID
                            ))
                        }
                    } catch {
                        await send(.friendshipMutationFailed(
                            error.localizedDescription,
                            reload: false,
                            userID: session.userID
                        ))
                    }
                }
                .cancellable(id: CancelID.friendship, cancelInFlight: true)

            case let .friendshipMutationCompleted(friendship, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                if state.snapshot == nil { state.snapshot = .empty() }
                state.snapshot?.apply(friendship)
                state.friendCandidate = nil
                state.inviteCodeInput = ""
                state.addFriendPresented = false
                state.isLoading = false
                state.clearFriendshipOperation()
                return refreshScheduling(state)

            case let .friendshipMutationFailed(message, reload, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                state.isLoading = false
                state.alertMessage = message
                if reload { state.clearFriendshipOperation() }
                return reload ? .send(.reloadFriendships) : .none

            case let .snapshotMutationCompleted(snapshot):
                state.availabilityRevision += 1
                state.isAvailabilityLoading = false
                applyBusinessSnapshot(snapshot, to: &state)
                state.isLoading = false
                revalidateSelection(&state)
                return refreshScheduling(state)

            case let .showReport(presented):
                state.reportPresented = presented
                if !presented { state.reportNote = "" }
                return .none

            case let .reportReasonChanged(reason):
                state.reportReason = reason
                return .none

            case let .reportNoteChanged(note):
                state.reportNote = String(note.prefix(500))
                return .none

            case .submitReportTapped:
                let reason = state.reportReason
                let note = state.reportNote
                state.isLoading = true
                return .run { send in
                    do { await send(.reportSubmitted(try await client.submitReport(reason, note))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .reportSubmitted(receipt):
                state.reportReceipt = receipt.reference
                state.reportPresented = false
                state.isLoading = false
                state.alertMessage = "通報を受け付けました（\(receipt.reference)）。"
                return .none

            case let .setBlockTarget(friend):
                state.blockTarget = friend
                return .none

            case let .confirmBlock(id):
                state.blockTarget = nil
                if !state.isDemo { return .send(.automaticScheduling(.send(.blockFriend(id)))) }
                return .run { send in await send(.snapshotMutationCompleted(client.block(id))) }

            case .toggleInvitationNotifications:
                state.invitationNotifications.toggle()
                return .none
            case .toggleResponseNotifications:
                state.responseNotifications.toggle()
                return .none
            case .togglePlanNotifications:
                state.planNotifications.toggle()
                return .none
            case .toggleReminder:
                state.reminderEnabled.toggle()
                return .none

            case let .showDeleteConfirmation(presented):
                state.deleteConfirmationPresented = presented
                return .none

            case let .deleteAccountAuthorized(credential):
                guard let session = state.authenticationSession else {
                    state.deleteConfirmationPresented = false
                    state.alertMessage = "セッションを確認できません。Appleでサインインし直してください。"
                    return .none
                }
                state.isLoading = true
                let operationID = state.deletionOperationID ?? UUID()
                state.deletionOperationID = operationID
                do {
                    try deletionStatusTokenStore.saveOperationID(operationID)
                } catch {
                    state.isLoading = false
                    state.alertMessage = "削除要求を安全に記録できませんでした。端末の状態を確認して再試行してください。"
                    return .none
                }
                let authorization = AccountDeletionAuthorization(
                    appleAuthorizationCode: credential.authorizationCode,
                    operationID: operationID,
                    accessToken: session.accessToken
                )
                return .run { send in
                    do {
                        var receipt = try await accountDeletionClient.submit(authorization)
                        var pendingReceiptSaved = false
                        if receipt.status == .actionRequired {
                            do {
                                try deletionStatusTokenStore.save(PendingAccountDeletion(
                                    reference: receipt.reference,
                                    statusToken: receipt.statusToken
                                ))
                                pendingReceiptSaved = true
                            } catch {
                                receipt = AccountDeletionReceipt(
                                    reference: receipt.reference,
                                    status: receipt.status,
                                    statusToken: receipt.statusToken,
                                    message: [
                                        receipt.message,
                                        "削除状況を端末へ保存できませんでした。受付番号を控えてください。",
                                    ].compactMap { $0 }.joined(separator: " ")
                                )
                            }
                        } else if receipt.status == .completed {
                            try? deletionStatusTokenStore.remove()
                        } else {
                            do {
                                try deletionStatusTokenStore.save(PendingAccountDeletion(
                                    reference: receipt.reference,
                                    statusToken: receipt.statusToken
                                ))
                                pendingReceiptSaved = true
                            } catch {
                                receipt = AccountDeletionReceipt(
                                    reference: receipt.reference,
                                    status: receipt.status,
                                    statusToken: receipt.statusToken,
                                    message: "削除状況を端末へ保存できませんでした。受付番号を控えてください。"
                                )
                            }
                        }
                        var signedOut = false
                        do {
                            try await authenticationClient.signOut()
                            signedOut = true
                        } catch {
                            receipt = AccountDeletionReceipt(
                                reference: receipt.reference,
                                status: receipt.status,
                                statusToken: receipt.statusToken,
                                message: [receipt.message, "端末セッションの削除を再試行します。"].compactMap { $0 }.joined(separator: " ")
                            )
                        }
                        if (receipt.status == .completed && signedOut) || pendingReceiptSaved {
                            try? deletionStatusTokenStore.removeOperationID()
                        }
                        await send(.deletionSubmitted(receipt))
                    } catch {
                        await send(.deletionSubmissionFailed(error.localizedDescription))
                    }
                }

            case let .deletionSubmitted(receipt):
                if let key = state.accountKey { firstMatchLocalStore.remove(key) }
                resetAccountScopedState(&state)
                state.accountDeletionReceipt = receipt
                let schedulingRevision = state.automaticScheduling.revision + 1
                state.automaticScheduling = .init()
                state.automaticScheduling.revision = schedulingRevision
                state.deletionOperationID = nil
                state.deletionRecoveryMessage = nil
                state.authenticationSession = nil
                state.snapshot = .empty()
                switch receipt.status {
                case .accepted:
                    state.snapshot?.deletionStatus = .accepted(reference: receipt.reference)
                case .processing:
                    state.snapshot?.deletionStatus = .processing(reference: receipt.reference)
                case .completed:
                    state.snapshot?.deletionStatus = .completed
                case .actionRequired:
                    state.snapshot?.deletionStatus = .actionRequired(
                        reference: receipt.reference,
                        message: receipt.message ?? "追加対応が必要です。"
                    )
                }
                state.deleteConfirmationPresented = false
                state.isLoading = false
                state.route = .deletionAccepted
                return .cancel(id: CancelID.friendship)

            case let .deletionSubmissionFailed(message):
                state.deleteConfirmationPresented = false
                state.isLoading = false
                state.alertMessage = message
                return .none
            }
        }
        .ifLet(\.$availabilityEditor, action: \.availabilityEditor) {
            AvailabilityEditorFeature()
        }
    }

    /// Writes the Domain validation result of the current timeline selection back to it,
    /// so past, out-of-window and overlapping ranges are marked as soon as they are picked.
    private func revalidateSelection(_ state: inout State) {
        guard let selection = state.homeTimeline.selection, !selection.isSaving else { return }
        let existing = state.snapshot?.availability ?? []
        state.homeTimeline.selection?.issue = availabilityIssue(selection.range, existing: existing)
    }

    private func availabilityIssue(_ range: QuarterRange, existing: [AvailabilitySlot]) -> AvailabilityValidationError? {
        let candidate = AvailabilitySlot(
            id: Self.selectionCandidateID,
            interval: TimeIntervalRange(id: Self.selectionCandidateID, start: range.start, end: range.end),
            category: nil,
            visibility: .privateUntilAccepted
        )
        let nonOverlapping = existing.filter {
            !$0.interval.overlaps(candidate.interval)
        }
        do {
            try AvailabilityPolicy.validate(candidate, now: now, existing: nonOverlapping, calendar: calendar)
            return nil
        } catch let error as AvailabilityValidationError {
            return error
        } catch {
            return .invalidInterval
        }
    }

    /// Every change is saved immediately, so the stored record is the source of truth for the current account.
    private func loadFirstMatchRecord(_ state: inout State) {
        guard let key = state.accountKey else { return }
        let record = firstMatchLocalStore.load(key)
        if record != state.firstMatchRecord { state.firstMatchRecord = record }
    }

    private func saveFirstMatchRecord(_ state: State) {
        guard let key = state.accountKey else { return }
        firstMatchLocalStore.save(key, state.firstMatchRecord)
    }

    /// Runs after every main-route action: completes the guide once a 参加OK exists (3.4)
    /// and shows each new 参加OK once as an in-app banner (8.1).
    private func evaluateFirstMatch(_ state: inout State) {
        guard let snapshot = state.snapshot, state.accountKey != nil else { return }
        loadFirstMatchRecord(&state)
        if state.firstMatchRecord.guide == .active,
           FirstMatchProgress.isCompleted(snapshot: snapshot, scheduling: state.automaticScheduling.snapshot) {
            state.firstMatchRecord.guide = .completed
            saveFirstMatchRecord(state)
        }
        let known = state.firstMatchRecord.seenParticipationKeys.union(state.shownParticipationKeys)
        let notices = ParticipationNoticeDetector.newNotices(hostings: snapshot.hostings, seenKeys: known)
        guard let latest = notices.last else { return }
        state.shownParticipationKeys.formUnion(ParticipationNoticeDetector.activeKeys(hostings: snapshot.hostings))
        let others = notices.count - 1
        state.participationBanner = ParticipationBanner(
            title: latest.isChange ? "\(latest.friend.displayName)さんが時間を変えました" : "\(latest.friend.displayName)さんが参加OK",
            detail: AvailabilityFormatting.friendlyRange(latest.interval, calendar: calendar, now: now) + (others > 0 ? "　ほか\(others)件" : "")
        )
    }

    /// Clears everything that belongs to the signed-in account (or the demo) at an account boundary,
    /// and invalidates in-flight results by advancing the revisions (requirement 11).
    private func resetAccountScopedState(_ state: inout State) {
        state.composer = nil
        state.reply = nil
        state.availabilityEditor = nil
        state.sentInvitation = nil
        state.participationBanner = nil
        state.shownParticipationKeys = []
        state.firstMatchRecord = FirstMatchRecord()
        state.hostingResponseOperationIDs = [:]
        state.hostingCancelOperationIDs = [:]
        state.calendarPresented = false
        state.inboxPresented = false
        state.addFriendPresented = false
        state.friendCandidate = nil
        state.inviteCodeInput = ""
        state.blockTarget = nil
        state.homeTimeline.selection = nil
        state.hostingLoadError = false
        state.hostingRevision += 1
        state.availabilityRevision += 1
        state.selectedTab = .home
    }

    private func hasActiveHosting(overlapping interval: TimeIntervalRange, in hostings: [Hosting]) -> Bool {
        hostings.contains {
            $0.status == .recruiting
                && $0.candidateRange.start < interval.end
                && interval.start < $0.candidateRange.end
        }
    }

    /// Placeholder id for validating a not-yet-created selection.
    private static let selectionCandidateID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    private func loadProfile(session: AuthenticationSession) -> Effect<Action> {
        .run { send in
            do { await send(.profileLoaded(try await profileClient.get(session.accessToken))) }
            catch {
                if let message = authenticationRejectionMessage(error) {
                    try? await authenticationClient.signOut()
                    await send(.authenticationInvalidated(message))
                } else {
                    await send(.profileLoadFailed(error.localizedDescription))
                }
            }
        }
    }

    private func refreshScheduling(_ state: State) -> Effect<Action> {
        guard let owner = state.accountKey, state.automaticScheduling.ownerID == owner else { return .none }
        return .send(.automaticScheduling(.refresh))
    }

    /// The explicit DEBUG demo uses the prototype scenario; every other path uses the injected business client.
    private func business(for state: State) -> HimatchClient {
#if DEBUG
        if state.isDemo { return demoScenarioClient.business }
#endif
        return liveClient
    }

    private func applyBusinessSnapshot(_ snapshot: AppSnapshot, to state: inout State) {
        if !state.isDemo, state.authenticationSession != nil, state.snapshot != nil {
            state.snapshot?.availability = snapshot.availability
        } else {
            state.snapshot = snapshot
        }
    }

    private func friendshipTransitionEffect(
        _ request: FriendRequest,
        _ transition: FriendRequestTransition,
        _ operationID: UUID,
        _ accessToken: String,
        _ userID: String
    ) -> Effect<Action> {
        .run { send in
            do {
                await send(.friendshipMutationCompleted(
                    try await friendshipClient.transitionRequest(
                        request.id,
                        transition,
                        request.version,
                        operationID,
                        accessToken
                    ),
                    userID: userID
                ))
            } catch let error as BackendClientError {
                if let message = authenticationRejectionMessage(error) {
                    try? await authenticationClient.signOut()
                    await send(.authenticationInvalidated(message))
                } else {
                    await send(.friendshipMutationFailed(
                        error.localizedDescription,
                        reload: isFriendshipConflict(error),
                        userID: userID
                    ))
                }
            } catch {
                await send(.friendshipMutationFailed(
                    error.localizedDescription,
                    reload: false,
                    userID: userID
                ))
            }
        }
        .cancellable(id: CancelID.friendship, cancelInFlight: true)
    }
}

private func authenticationRejectionMessage(_ error: Error) -> String? {
    guard case let BackendClientError.response(status, message) = error,
          status == 401 || status == 403
    else { return nil }
    return message ?? "サインイン状態を確認できません。Appleでサインインし直してください。"
}

private func isFriendshipConflict(_ error: BackendClientError) -> Bool {
    guard case .response(409, _) = error else { return false }
    return true
}

/// Transient in-app notice for a new 参加OK (8.1).
struct ParticipationBanner: Equatable, Sendable {
    var title: String
    var detail: String
}
