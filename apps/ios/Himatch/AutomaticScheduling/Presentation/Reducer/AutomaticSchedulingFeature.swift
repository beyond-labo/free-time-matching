import ComposableArchitecture
import Foundation

@Reducer
struct AutomaticSchedulingFeature {
    @ObservableState
    struct State: Equatable {
        var ownerID: String?
        var revision = 0
        var snapshot: SchedulingSnapshot?
        var isLoading = false
        var isSending = false
        var shareAcceptance: [UUID: Bool] = [:]
        var pendingCommand: SchedulingCommand?
        var operationID: UUID?
        var error: String?
        var message: String?
        var reportReceipt: UUID?
        var notificationMessage: String?
        var isRegisteringNotifications = false
        var canMutate: Bool { ownerID != nil && snapshot != nil && !isSending && pendingCommand == nil }
    }

    enum Action: Equatable {
        case activate(String)
        case reset
        case refresh
        case loaded(SchedulingSnapshot, owner: String, revision: Int)
        case failed(SchedulingFailure, owner: String, revision: Int, mutation: Bool)
        case setShareAcceptance(UUID, Bool)
        case send(SchedulingCommand)
        case retry
        case mutationCompleted(SchedulingSnapshot, SchedulingCommand, owner: String, revision: Int)
        case requestNotifications
        case disableNotifications
        case notificationsCompleted(String, owner: String)
        case notificationsFailed(SchedulingFailure, owner: String)
        case delegate(Delegate)
        enum Delegate: Equatable { case authenticationInvalidated, safetyChanged }
    }

    @Dependency(\.automaticSchedulingEffects) var effects
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .activate(owner):
                if state.ownerID != owner {
                    let revision = state.revision + 1
                    state = State()
                    state.ownerID = owner
                    state.revision = revision
                }
                return .send(.refresh)
            case .reset:
                let revision = state.revision + 1
                state = State()
                state.revision = revision
                return .none
            case .refresh:
                guard let owner = state.ownerID, !state.isSending else { return .none }
                state.revision += 1
                state.isLoading = true
                let revision = state.revision
                return .run { send in
                    do { await send(.loaded(try await effects.load(owner), owner: owner, revision: revision)) }
                    catch is CancellationError { }
                    catch { await send(.failed(error as? SchedulingFailure ?? .unavailable, owner: owner, revision: revision, mutation: false)) }
                }
            case let .loaded(snapshot, owner, revision):
                guard state.ownerID == owner, state.revision == revision else { return .none }
                state.snapshot = snapshot
                state.isLoading = false
                if state.pendingCommand == nil { state.error = nil }
                return .none
            case let .setShareAcceptance(id, value):
                guard state.canMutate else { return .none }
                state.shareAcceptance[id] = value
                return .none
            case let .send(command):
                guard state.canMutate else { return .none }
                state.pendingCommand = command
                state.operationID = uuid()
                return perform(&state)
            case .retry:
                guard !state.isSending, state.pendingCommand != nil else { return .none }
                return perform(&state)
            case let .mutationCompleted(snapshot, command, owner, revision):
                guard state.ownerID == owner, state.revision == revision else { return .none }
                let completedOperationID = state.operationID
                state.snapshot = snapshot
                state.isSending = false
                state.pendingCommand = nil
                state.operationID = nil
                state.error = nil
                switch command {
                case .report, .reportFriend:
                    state.reportReceipt = completedOperationID
                    state.message = "通報を受け付けました。"
                case .feedback: state.message = "任意の回答を保存しました。"
                case .blockFriend, .blockProposal:
                    state.message = "ブロックしました。"
                    return .send(.delegate(.safetyChanged))
                default: state.message = nil
                }
                return .none
            case let .failed(failure, owner, revision, mutation):
                guard state.ownerID == owner, state.revision == revision else { return .none }
                state.isLoading = false
                state.isSending = false
                state.error = failure.localizedDescription
                if failure == .unauthorized {
                    state.snapshot = nil
                    state.pendingCommand = nil
                    state.operationID = nil
                    return .send(.delegate(.authenticationInvalidated))
                }
                if mutation, failure == .conflict || failure == .rejected {
                    state.pendingCommand = nil
                    state.operationID = nil
                    state.message = failure.localizedDescription
                    return .send(.refresh)
                }
                return .none
            case .requestNotifications, .disableNotifications:
                guard let owner = state.ownerID, !state.isRegisteringNotifications else { return .none }
                state.isRegisteringNotifications = true
                let disabling = action == .disableNotifications
                return .run { send in
                    do {
                        if disabling {
                            try await effects.disableDevice(owner)
                            await send(.notificationsCompleted("この端末の通知を停止しました。", owner: owner))
                            return
                        }
                        let allowed = try await effects.requestNotifications(owner)
                        await send(.notificationsCompleted(allowed ? "通知を有効にしました。" : "通知は許可されていません。受信箱から利用できます。", owner: owner))
                    } catch {
                        await send(.notificationsFailed(error as? SchedulingFailure ?? .unavailable, owner: owner))
                    }
                }
            case let .notificationsFailed(failure, owner):
                guard state.ownerID == owner else { return .none }
                state.isRegisteringNotifications = false
                if failure == .unauthorized {
                    state.snapshot = nil
                    state.pendingCommand = nil
                    state.operationID = nil
                    state.error = failure.localizedDescription
                    return .send(.delegate(.authenticationInvalidated))
                }
                state.notificationMessage = "通知登録を確認できません。再試行できます。受信箱は引き続き利用できます。"
                return .none
            case let .notificationsCompleted(message, owner):
                guard state.ownerID == owner else { return .none }
                state.isRegisteringNotifications = false
                state.notificationMessage = message
                return .none
            case .delegate: return .none
            }
        }
    }

    private func perform(_ state: inout State) -> Effect<Action> {
        guard let owner = state.ownerID, let command = state.pendingCommand, let operationID = state.operationID else { return .none }
        state.revision += 1
        let revision = state.revision
        state.isSending = true
        state.isLoading = false
        state.error = nil
        state.message = nil
        state.reportReceipt = nil
        return .run { send in
            do { await send(.mutationCompleted(try await effects.execute(command, operationID, owner), command, owner: owner, revision: revision)) }
            catch is CancellationError { }
            catch { await send(.failed(error as? SchedulingFailure ?? .unavailable, owner: owner, revision: revision, mutation: true)) }
        }
    }
}
