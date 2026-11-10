import ComposableArchitecture
import Foundation

/// Where the composer was opened from; the given time or friend is carried over without re-entry (4.4–4.6).
enum InvitationStart: Equatable, Sendable {
    case blank
    case candidate(TimeCandidate)
    case range(QuarterRange)
    case friend(UUID)
}

/// Input state of the 「友達を誘う」 screen. API calls, idempotency and conflicts stay in the parent (ios-hosting 7.x).
@Reducer
struct InvitationComposerFeature {
    enum MissingItem: Equatable, Sendable {
        case time
        case friends
        case mode
        case area
        case availabilityMetadata

        var message: String {
            switch self {
            case .time: "いつにするか選んでください"
            case .friends: "誘う友達を選んでください"
            case .mode: "オンラインか会うかを選んでください"
            case .area: "会うエリアを選んでください"
            case .availabilityMetadata: "重なるあなたの暇の設定を選んでください"
            }
        }
    }

    /// The host's own availability that the candidate range merges with has different attributes (5.8).
    struct AvailabilityConflict: Equatable, Sendable {
        var existing: [AvailabilitySlot]
        var chosen: HostingAvailabilityMetadata?
    }

    @ObservableState
    struct State: Equatable {
        var range: QuarterRange?
        var selectedCandidateID: String?
        var isCustomTime = false
        var candidates: [TimeCandidate]
        var friends: [FriendProfile]
        var selectedFriendIDs: Set<UUID> = []
        var mode: HostingMode?
        var area: HostingArea?
        var category: ActivityCategory?
        var availability: [AvailabilitySlot]
        var availabilityMetadata = HostingAvailabilityMetadata(category: nil, visibility: .privateUntilAccepted)
        var availabilityConflict: AvailabilityConflict?
        var operationID: UUID
        var isSubmitting = false
        var errorMessage: String?
        var now: Date

        init(
            start: InvitationStart,
            friends: [FriendProfile],
            availability: [AvailabilitySlot],
            candidates: [TimeCandidate],
            lastMeeting: LastMeeting?,
            now: Date,
            operationID: UUID
        ) {
            self.friends = friends
            self.availability = availability
            self.candidates = candidates
            self.now = now
            self.operationID = operationID
            self.mode = lastMeeting?.mode
            self.area = lastMeeting?.mode == .offline ? lastMeeting?.area : nil
            switch start {
            case .blank:
                break
            case let .candidate(candidate):
                range = QuarterRange(start: candidate.range.start, end: candidate.range.end)
                selectedCandidateID = candidate.id
            case let .range(value):
                range = value
                selectedCandidateID = candidates.first { $0.range.start == value.start && $0.range.end == value.end }?.id
                isCustomTime = selectedCandidateID == nil
            case let .friend(id):
                if friends.contains(where: { $0.id == id }) { selectedFriendIDs = [id] }
            }
            Self.resolveAvailabilityMetadata(&self)
        }

        var missingItem: MissingItem? {
            if range == nil { return .time }
            if selectedFriendIDs.isEmpty { return .friends }
            guard let mode else { return .mode }
            if mode == .offline, area == nil { return .area }
            if let availabilityConflict, availabilityConflict.chosen == nil { return .availabilityMetadata }
            return nil
        }

        var selectedFriends: [FriendProfile] { friends.filter { selectedFriendIDs.contains($0.id) } }
        var allFriendsSelected: Bool { !friends.isEmpty && selectedFriendIDs.count == friends.count }
        var canSubmit: Bool { missingItem == nil && !isSubmitting }

        /// Picks the availability attributes without asking when nothing new would be shared (5.7, 5.8).
        static func resolveAvailabilityMetadata(_ state: inout State) {
            state.availabilityConflict = nil
            state.availabilityMetadata = HostingAvailabilityMetadata(category: nil, visibility: .privateUntilAccepted)
            guard let range = state.range else { return }
            let connected = connectedAvailability(range, existing: state.availability)
            if let covering = connected.first(where: { $0.interval.start <= range.start && range.end <= $0.interval.end }),
               connected.allSatisfy({ $0.category == covering.category && $0.visibility == covering.visibility }) {
                state.availabilityMetadata = HostingAvailabilityMetadata(category: covering.category, visibility: covering.visibility)
                return
            }
            let defaults = state.availabilityMetadata
            if connected.allSatisfy({ $0.category == defaults.category && $0.visibility == defaults.visibility }) { return }
            state.availabilityConflict = AvailabilityConflict(existing: connected, chosen: nil)
        }

        /// Existing slots that overlap or touch the range, followed transitively (same rule as the OR merge).
        static func connectedAvailability(_ range: QuarterRange, existing: [AvailabilitySlot]) -> [AvailabilitySlot] {
            var lower = range.start
            var upper = range.end
            var included = Set<UUID>()
            var changed = true
            while changed {
                changed = false
                for slot in existing where !included.contains(slot.id) && slot.interval.start <= upper && lower <= slot.interval.end {
                    included.insert(slot.id)
                    lower = min(lower, slot.interval.start)
                    upper = max(upper, slot.interval.end)
                    changed = true
                }
            }
            return existing.filter { included.contains($0.id) }
        }
    }

    enum Action: Equatable {
        case candidateSelected(String)
        case customTimeSelected
        case daySelected(Date)
        case startChanged(Date)
        case endChanged(Date)
        case friendToggled(UUID)
        case allFriendsToggled
        case modeSelected(HostingMode)
        case areaSelected(HostingArea)
        case categoryToggled(ActivityCategory)
        case availabilityMetadataChosen(ActivityCategory?, AvailabilityVisibility)
        case submitTapped
        case submissionFailed(String)
        case closeTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case submit(HostingDraft)
            case close
        }
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.calendar) var calendar

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .candidateSelected(id):
                guard let candidate = state.candidates.first(where: { $0.id == id }) else { return .none }
                state.selectedCandidateID = id
                state.isCustomTime = false
                state.range = QuarterRange(start: candidate.range.start, end: candidate.range.end)
                return changed(&state)

            case .customTimeSelected:
                state.isCustomTime = true
                state.selectedCandidateID = nil
                if state.range == nil {
                    let start = AvailabilityPolicy.nextQuarterHour(after: state.now, calendar: calendar)
                    state.range = QuarterRange(start: start, end: Self.clampedEnd(start.addingTimeInterval(2 * 3600), start: start, calendar: calendar))
                }
                return changed(&state)

            case let .daySelected(day):
                guard let range = state.range else { return .none }
                let offset = range.start.timeIntervalSince(calendar.startOfDay(for: range.start))
                let duration = range.duration
                var start = calendar.startOfDay(for: day).addingTimeInterval(offset)
                let earliest = AvailabilityPolicy.nextQuarterHour(after: state.now, calendar: calendar)
                if start < earliest { start = earliest }
                state.range = QuarterRange(start: start, end: Self.clampedEnd(start.addingTimeInterval(duration), start: start, calendar: calendar))
                state.selectedCandidateID = nil
                return changed(&state)

            case let .startChanged(start):
                guard let range = state.range else { return .none }
                let duration = max(range.duration, AvailabilityPolicy.quarterHour)
                state.range = QuarterRange(start: start, end: Self.clampedEnd(start.addingTimeInterval(duration), start: start, calendar: calendar))
                state.selectedCandidateID = nil
                return changed(&state)

            case let .endChanged(end):
                guard let range = state.range, end > range.start else { return .none }
                state.range = QuarterRange(start: range.start, end: end)
                state.selectedCandidateID = nil
                return changed(&state)

            case let .friendToggled(id):
                if state.selectedFriendIDs.contains(id) { state.selectedFriendIDs.remove(id) } else { state.selectedFriendIDs.insert(id) }
                return changed(&state, resolve: false)

            case .allFriendsToggled:
                state.selectedFriendIDs = state.allFriendsSelected ? [] : Set(state.friends.map(\.id))
                return changed(&state, resolve: false)

            case let .modeSelected(mode):
                state.mode = mode
                if mode == .online { state.area = nil }
                return changed(&state, resolve: false)

            case let .areaSelected(area):
                state.area = area
                return changed(&state, resolve: false)

            case let .categoryToggled(category):
                state.category = state.category == category ? nil : category
                return changed(&state, resolve: false)

            case let .availabilityMetadataChosen(category, visibility):
                let metadata = HostingAvailabilityMetadata(category: category, visibility: visibility)
                state.availabilityConflict?.chosen = metadata
                state.availabilityMetadata = metadata
                return changed(&state, resolve: false)

            case .submitTapped:
                guard state.canSubmit, let range = state.range, let mode = state.mode else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                let draft = HostingDraft(
                    mode: mode,
                    area: mode == .offline ? state.area : nil,
                    category: state.category,
                    start: range.start,
                    duration: range.duration,
                    friends: state.selectedFriends,
                    availabilityMetadata: state.availabilityMetadata,
                    availabilityCategory: state.availabilityMetadata.category,
                    availabilityVisibility: state.availabilityMetadata.visibility,
                    operationID: state.operationID
                )
                return .send(.delegate(.submit(draft)))

            case let .submissionFailed(message):
                state.isSubmitting = false
                state.errorMessage = message
                return .none

            case .closeTapped:
                // Closing while sending would let a retry issue a second operation ID (5.x).
                guard !state.isSubmitting else { return .none }
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }

    /// Every meaningful input change gets a new operation ID so a retry never replays a different payload.
    private func changed(_ state: inout State, resolve: Bool = true) -> Effect<Action> {
        if resolve { State.resolveAvailabilityMetadata(&state) }
        state.operationID = uuid()
        state.errorMessage = nil
        return .none
    }

    /// The composer's own picker keeps the end within the same day and the 14-day window.
    static func clampedEnd(_ end: Date, start: Date, calendar: Calendar) -> Date {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? end
        return max(min(end, dayEnd), start.addingTimeInterval(AvailabilityPolicy.quarterHour))
    }
}
