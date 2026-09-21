import ComposableArchitecture
import Foundation

private enum HimatchClientKey: DependencyKey {
    static let liveValue = HimatchClient(
        load: { fatalError("HimatchClient is not injected") },
        saveProfile: { _, _ in fatalError("HimatchClient is not injected") },
        addAvailability: { _ in fatalError("HimatchClient is not injected") },
        removeAvailability: { _ in fatalError("HimatchClient is not injected") },
        createHosting: { _ in fatalError("HimatchClient is not injected") },
        acceptInvitation: { _, _ in fatalError("HimatchClient is not injected") },
        confirmHosting: { _ in fatalError("HimatchClient is not injected") },
        acceptRequest: { _ in fatalError("HimatchClient is not injected") },
        removeFriend: { _ in fatalError("HimatchClient is not injected") },
        submitReport: { _, _ in fatalError("HimatchClient is not injected") },
        block: { _ in fatalError("HimatchClient is not injected") },
        deleteAccount: { fatalError("HimatchClient is not injected") }
    )
    static let testValue = liveValue
}

extension DependencyValues {
    var himatchClient: HimatchClient {
        get { self[HimatchClientKey.self] }
        set { self[HimatchClientKey.self] = newValue }
    }
}

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        enum Route: Equatable {
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

        var route: Route = .onboarding
        var selectedTab: Tab = .home
        var snapshot: AppSnapshot?
        var isLoading = false
        var alertMessage: String?

        var profileName = "ひまり"
        var profileIcon = "sun.max.fill"

        var availabilityEditorPresented = false
        var availabilityStart = AvailabilityPolicy.nextQuarterHour(after: Date())
        var availabilityDurationHours = 2
        var availabilityCategory: ActivityCategory?
        var availabilityVisibility: AvailabilityVisibility = .privateUntilAccepted

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
        var reportPresented = false
        var reportReason: ReportReason = .nuisanceInvitation
        var reportNote = ""
        var reportReceipt: String?
        var blockTarget: FriendProfile?
        var deleteConfirmationPresented = false

        var invitationNotifications = true
        var responseNotifications = true
        var planNotifications = true
        var reminderEnabled = false
    }

    enum Action {
        case task
        case snapshotLoaded(AppSnapshot)
        case operationFailed(String)
        case dismissAlert

        case appleAuthorizationCompleted(String?)
        case startDemo
        case profileNameChanged(String)
        case profileIconChanged(String)
        case saveProfileTapped
        case profileSaved(AppSnapshot)
        case selectTab(State.Tab)
        case logoutTapped

        case showAvailabilityEditor(Bool)
        case availabilityStartChanged(Date)
        case availabilityDurationChanged(Int)
        case availabilityCategoryChanged(ActivityCategory?)
        case availabilityVisibilityChanged(AvailabilityVisibility)
        case saveAvailabilityTapped
        case availabilitySaved(AppSnapshot)
        case removeAvailability(UUID)

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
        case acceptRequest(UUID)
        case removeFriend(UUID)
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
        case deleteAccountTapped
        case deletionAccepted(AppSnapshot)
    }

    @Dependency(\.himatchClient) var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { send in
                    await send(.snapshotLoaded(client.load()))
                }

            case let .snapshotLoaded(snapshot):
                state.snapshot = snapshot
                state.profileName = snapshot.profileName
                state.profileIcon = snapshot.profileIcon
                state.isLoading = false
                return .none

            case let .operationFailed(message):
                state.isLoading = false
                state.alertMessage = message
                return .none

            case .dismissAlert:
                state.alertMessage = nil
                return .none

            case let .appleAuthorizationCompleted(code):
                guard code != nil else {
                    state.alertMessage = "Apple認証を完了できませんでした。もう一度お試しください。"
                    return .none
                }
                state.alertMessage = "Apple認証のサーバー検証はBackend接続後に利用できます。現在はデモをお試しください。"
                return .none

            case .startDemo:
                state.route = .profile
                return .none

            case let .profileNameChanged(value):
                state.profileName = value
                return .none

            case let .profileIconChanged(value):
                state.profileIcon = value
                return .none

            case .saveProfileTapped:
                state.isLoading = true
                let name = state.profileName
                let icon = state.profileIcon
                return .run { send in
                    do { await send(.profileSaved(try await client.saveProfile(name, icon))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .profileSaved(snapshot):
                state.snapshot = snapshot
                state.isLoading = false
                state.route = .main
                return .none

            case let .selectTab(tab):
                state.selectedTab = tab
                return .none

            case .logoutTapped:
                state.route = .onboarding
                state.selectedTab = .home
                return .none

            case let .showAvailabilityEditor(presented):
                state.availabilityEditorPresented = presented
                if presented {
                    state.availabilityStart = AvailabilityPolicy.nextQuarterHour(after: Date())
                    state.availabilityDurationHours = 2
                    state.availabilityCategory = nil
                    state.availabilityVisibility = .privateUntilAccepted
                }
                return .none

            case let .availabilityStartChanged(date):
                state.availabilityStart = date
                return .none

            case let .availabilityDurationChanged(hours):
                state.availabilityDurationHours = hours
                return .none

            case let .availabilityCategoryChanged(category):
                state.availabilityCategory = category
                return .none

            case let .availabilityVisibilityChanged(visibility):
                state.availabilityVisibility = visibility
                return .none

            case .saveAvailabilityTapped:
                let start = state.availabilityStart
                let slot = AvailabilitySlot(
                    interval: TimeIntervalRange(
                        start: start,
                        end: start.addingTimeInterval(TimeInterval(state.availabilityDurationHours) * 60 * 60)
                    ),
                    category: state.availabilityCategory,
                    visibility: state.availabilityVisibility
                )
                state.isLoading = true
                return .run { send in
                    do { await send(.availabilitySaved(try await client.addAvailability(slot))) }
                    catch { await send(.operationFailed(error.localizedDescription)) }
                }

            case let .availabilitySaved(snapshot):
                state.snapshot = snapshot
                state.availabilityEditorPresented = false
                state.isLoading = false
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
                return .none

            case let .inviteCodeChanged(value):
                state.inviteCodeInput = value
                return .none

            case let .acceptRequest(id):
                return .run { send in await send(.snapshotMutationCompleted(client.acceptRequest(id))) }

            case let .removeFriend(id):
                return .run { send in await send(.snapshotMutationCompleted(client.removeFriend(id))) }

            case let .snapshotMutationCompleted(snapshot):
                state.snapshot = snapshot
                state.isLoading = false
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

            case .deleteAccountTapped:
                state.isLoading = true
                return .run { send in await send(.deletionAccepted(client.deleteAccount())) }

            case let .deletionAccepted(snapshot):
                state.snapshot = snapshot
                state.deleteConfirmationPresented = false
                state.isLoading = false
                state.route = .deletionAccepted
                return .none
            }
        }
    }
}
