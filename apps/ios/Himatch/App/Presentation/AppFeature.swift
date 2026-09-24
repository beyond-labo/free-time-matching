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
        var authenticationSession: AuthenticationSession?
        var isDemo = false
        var isLoading = false
        var alertMessage: String?

        var profileName = "ひまり"
        var profileIcon = PresetProfileIcon.sun.rawValue
        var profileValidationMessage: String?

        var homeTimeline = HomeTimelineFeature.State()
        @Presents var availabilityEditor: AvailabilityEditorFeature.State?
        var hostingListPresented = false

        var hostingEditorPresented = false
        var hostingMode: HostingMode = .online
        var hostingArea: HostingArea = .discussLater
        var hostingCategory: ActivityCategory?
        var hostingStart = AvailabilityPolicy.nextQuarterHour(after: Date()).addingTimeInterval(24 * 60 * 60)
        var hostingDurationHours = 1
        var selectedFriendIDs: Set<UUID> = []

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
        case profileLoadFailed(String)
        case startDemo
        case profileNameChanged(String)
        case profileIconChanged(String)
        case saveProfileTapped
        case profileSaved(AppSnapshot)
        case profileSaveFailed(String)
        case selectTab(State.Tab)
        case logoutTapped
        case logoutCompleted

        case homeTimeline(HomeTimelineFeature.Action)
        case availabilityEditor(PresentationAction<AvailabilityEditorFeature.Action>)
        case removeAvailability(UUID)
        case quickSaveSucceeded(AppSnapshot, slotID: UUID)
        case quickSaveFailed(String)
        case showHostingList(Bool)

        case showHostingEditor(Bool)
        case hostingModeChanged(HostingMode)
        case hostingAreaChanged(HostingArea)
        case hostingCategoryChanged(ActivityCategory?)
        case hostingStartChanged(Date)
        case hostingDurationChanged(Int)
        case toggleFriend(UUID)
        case createHostingTapped
        case hostingCreated(AppSnapshot)
        case confirmHosting(UUID)
        case acceptInvitation(UUID)

        case showInbox(Bool)
        case showAddFriend(Bool)
        case inviteCodeChanged(String)
        case reloadFriendships
        case friendshipsLoaded(FriendshipSnapshot, userID: String)
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

    @Dependency(\.himatchClient) var client
    @Dependency(\.authenticationClient) var authenticationClient
    @Dependency(\.friendshipClient) var friendshipClient
    @Dependency(\.profileClient) var profileClient
    @Dependency(\.accountDeletionClient) var accountDeletionClient
    @Dependency(\.deletionStatusTokenStore) var deletionStatusTokenStore
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Scope(state: \.homeTimeline, action: \.homeTimeline) {
            HomeTimelineFeature()
        }
        Reduce { state, action in
            switch action {
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
                    state.authenticationSession = session
                    guard state.route != .deletionAccepted else { return .none }
                    return .merge(
                        .cancel(id: CancelID.friendship),
                        loadProfile(session: session)
                    )
                case .signedOut:
                    guard state.route != .launching else { return .none }
                    state.authenticationSession = nil
                    guard state.route != .deletionAccepted else { return .none }
                    state.snapshot = nil
                    state.route = .onboarding
                    state.isLoading = false
                    return .cancel(id: CancelID.friendship)
                }

            case let .authenticationInvalidated(message):
                state.authenticationSession = nil
                state.snapshot = nil
                state.isDemo = false
                state.isLoading = false
                state.route = .onboarding
                state.alertMessage = message
                return .cancel(id: CancelID.friendship)

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
                return state.isDemo || state.authenticationSession == nil
                    ? .none
                    : .send(.reloadFriendships)

            case let .profileLoadFailed(message):
                state.isLoading = false
                state.alertMessage = message
                state.route = .profile
                return .none

            case .startDemo:
                state.isDemo = true
                state.route = .profile
                state.isLoading = false
                return .none

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
                return state.isDemo || state.authenticationSession == nil
                    ? .none
                    : .send(.reloadFriendships)

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
                    .run { send in
                        do {
                            try await authenticationClient.signOut()
                            await send(.logoutCompleted)
                        } catch {
                            await send(.operationFailed(error.localizedDescription))
                        }
                    }
                )

            case .logoutCompleted:
                state = State()
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

            case let .homeTimeline(.delegate(.quickSave(range))):
                guard let selection = state.homeTimeline.selection,
                      selection.range == range,
                      !selection.isSaving
                else { return .none }
                // Re-validate right before saving: the clock or the own slots may have changed.
                if let issue = availabilityIssue(range, existing: state.snapshot?.availability ?? []) {
                    state.homeTimeline.selection?.issue = issue
                    return .none
                }
                let slotID = uuid()
                let slot = AvailabilitySlot(
                    id: slotID,
                    interval: TimeIntervalRange(id: slotID, start: range.start, end: range.end),
                    category: nil,
                    visibility: .privateUntilAccepted
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
                state.snapshot = snapshot
                state.homeTimeline.selection = nil
                state.homeTimeline.lastSavedItem = .availability(slotID)
                state.homeTimeline.quickSaveSuccessCount += 1
                return .none

            case let .quickSaveFailed(message):
                state.homeTimeline.selection?.isSaving = false
                state.homeTimeline.selection?.saveError = message
                return .none

            case let .availabilityEditor(.presented(.delegate(.saved(snapshot)))):
                let savedStart = state.availabilityEditor?.start
                state.snapshot = snapshot
                state.availabilityEditor = nil
                state.homeTimeline.selection = nil
                if let savedStart {
                    state.homeTimeline.focus(on: savedStart, item: nil, now: now, calendar: calendar)
                }
                return .none

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

            case let .showHostingList(presented):
                state.hostingListPresented = presented
                return .none

            case let .removeAvailability(id):
                state.isLoading = true
                return .run { send in
                    await send(.snapshotMutationCompleted(client.removeAvailability(id)))
                }

            case let .showHostingEditor(presented):
                state.hostingEditorPresented = presented
                if presented {
                    state.hostingMode = .online
                    state.hostingArea = .discussLater
                    state.hostingCategory = nil
                    state.hostingDurationHours = 1
                    state.selectedFriendIDs = []
                }
                return .none

            case let .hostingModeChanged(mode):
                state.hostingMode = mode
                return .none

            case let .hostingAreaChanged(area):
                state.hostingArea = area
                return .none

            case let .hostingCategoryChanged(category):
                state.hostingCategory = category
                return .none

            case let .hostingStartChanged(date):
                state.hostingStart = date
                return .none

            case let .hostingDurationChanged(hours):
                state.hostingDurationHours = hours
                return .none

            case let .toggleFriend(id):
                if state.selectedFriendIDs.contains(id) { state.selectedFriendIDs.remove(id) }
                else { state.selectedFriendIDs.insert(id) }
                return .none

            case .createHostingTapped:
                guard let snapshot = state.snapshot else { return .none }
                let draft = HostingDraft(
                    mode: state.hostingMode,
                    area: state.hostingMode == .offline ? state.hostingArea : nil,
                    category: state.hostingCategory,
                    start: state.hostingStart,
                    duration: TimeInterval(state.hostingDurationHours) * 60 * 60,
                    friends: snapshot.friends.filter { state.selectedFriendIDs.contains($0.id) }
                )
                state.isLoading = true
                return .run { send in
                    do { await send(.hostingCreated(try await client.createHosting(draft))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .hostingCreated(snapshot):
                state.snapshot = snapshot
                state.hostingEditorPresented = false
                state.isLoading = false
                state.alertMessage = "募集を開始しました。参加OKの回答があると、ここに表示されます。"
                return .none

            case let .confirmHosting(id):
                state.isLoading = true
                return .run { send in
                    do { await send(.snapshotMutationCompleted(try await client.confirmHosting(id))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .acceptInvitation(id):
                guard let invitation = state.snapshot?.invitations.first(where: { $0.id == id }) else { return .none }
                let interval = TimeIntervalRange(
                    start: invitation.candidateRange.start,
                    end: invitation.candidateRange.start.addingTimeInterval(invitation.requiredDuration)
                )
                state.isLoading = true
                return .run { send in
                    do { await send(.snapshotMutationCompleted(try await client.acceptInvitation(id, interval))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .showInbox(presented):
                state.inboxPresented = presented
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
                state.isLoading = true
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
                            await send(.friendshipMutationFailed(
                                error.localizedDescription,
                                reload: false,
                                userID: session.userID
                            ))
                        }
                    }
                }
                .cancellable(id: CancelID.friendship, cancelInFlight: true)

            case let .friendshipsLoaded(friendship, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                if state.snapshot == nil { state.snapshot = .empty() }
                state.snapshot?.apply(friendship)
                state.isLoading = false
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
                return .none

            case let .friendshipMutationFailed(message, reload, userID):
                guard state.authenticationSession?.userID == userID else { return .none }
                state.isLoading = false
                state.alertMessage = message
                if reload { state.clearFriendshipOperation() }
                return reload ? .send(.reloadFriendships) : .none

            case let .snapshotMutationCompleted(snapshot):
                state.snapshot = snapshot
                state.isLoading = false
                revalidateSelection(&state)
                return .none

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
                state.accountDeletionReceipt = receipt
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
        do {
            try AvailabilityPolicy.validate(candidate, now: now, existing: existing, calendar: calendar)
            return nil
        } catch let error as AvailabilityValidationError {
            return error
        } catch {
            return .invalidInterval
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
