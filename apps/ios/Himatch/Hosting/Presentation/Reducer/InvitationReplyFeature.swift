import ComposableArchitecture
import Foundation

/// Reply to an invitation from another host. Nothing is preselected; one tap sends 参加OK (7.2–7.8, 7.10).
@Reducer
struct InvitationReplyFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var invitation: Hosting
        var choice: ReplyChoice?
        var customRange: TimeIntervalRange
        var isSubmitting = false
        var errorMessage: String?
        var now: Date

        var id: UUID { invitation.id }

        init(invitation: Hosting, now: Date) {
            self.invitation = invitation
            self.now = now
            let candidate = invitation.candidateRange
            let defaultEnd = min(candidate.end, candidate.start.addingTimeInterval(3600))
            customRange = TimeIntervalRange(start: candidate.start, end: defaultEnd)
            if invitation.myInvitation?.status == .accepted, let current = invitation.myInvitation?.intervals?.first {
                choice = ReplyChoicePolicy.presets(for: candidate).first {
                    $0.range.start == current.start && $0.range.end == current.end
                }?.choice ?? .custom
                customRange = TimeIntervalRange(start: current.start, end: current.end)
            }
        }

        var presets: [(choice: ReplyChoice, range: TimeIntervalRange)] {
            ReplyChoicePolicy.presets(for: invitation.candidateRange)
        }

        var selectedRange: TimeIntervalRange? {
            guard let choice else { return nil }
            return ReplyChoicePolicy.range(for: choice, candidate: invitation.candidateRange, custom: customRange)
        }

        var hasAccepted: Bool { invitation.myInvitation?.status == .accepted }

        /// Open and before the deadline (7.9).
        var canRespond: Bool { invitation.status == .recruiting && now < invitation.answerDeadline }

        var canAccept: Bool { canRespond && selectedRange != nil && !isSubmitting }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.invitation == rhs.invitation && lhs.choice == rhs.choice && lhs.customRange.start == rhs.customRange.start
                && lhs.customRange.end == rhs.customRange.end && lhs.isSubmitting == rhs.isSubmitting
                && lhs.errorMessage == rhs.errorMessage && lhs.now == rhs.now
        }
    }

    enum Action: Equatable {
        case choiceSelected(ReplyChoice)
        case customStartChanged(Date)
        case customEndChanged(Date)
        case acceptTapped
        case declineTapped
        case withdrawTapped
        case submissionFailed(String)
        case closeTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case respond(HostingInvitation.Status, [TimeIntervalRange])
            case close
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .choiceSelected(choice):
                state.choice = choice
                state.errorMessage = nil
                return .none

            case let .customStartChanged(start):
                let candidate = state.invitation.candidateRange
                guard start >= candidate.start, start < candidate.end else { return .none }
                var end = state.customRange.end
                if end <= start { end = min(candidate.end, start.addingTimeInterval(3600)) }
                state.customRange = TimeIntervalRange(start: start, end: end)
                state.choice = .custom
                return .none

            case let .customEndChanged(end):
                let candidate = state.invitation.candidateRange
                guard end > state.customRange.start, end <= candidate.end else { return .none }
                state.customRange = TimeIntervalRange(start: state.customRange.start, end: end)
                state.choice = .custom
                return .none

            case .acceptTapped:
                guard state.canAccept, let range = state.selectedRange else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                return .send(.delegate(.respond(.accepted, [TimeIntervalRange(start: range.start, end: range.end)])))

            case .declineTapped, .withdrawTapped:
                guard state.canRespond, !state.isSubmitting else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                return .send(.delegate(.respond(.declined, [])))

            case let .submissionFailed(message):
                state.isSubmitting = false
                state.errorMessage = message
                return .none

            case .closeTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }
}
