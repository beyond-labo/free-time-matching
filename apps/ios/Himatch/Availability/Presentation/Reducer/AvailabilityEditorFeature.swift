import ComposableArchitecture
import Foundation

/// New-availability sheet. Holds explicit start/end in 15-minute steps and validates with
/// `AvailabilityPolicy` on every change; saving goes through the existing `HimatchClient`.
@Reducer
struct AvailabilityEditorFeature {
    @ObservableState
    struct State: Equatable {
        static let durationPresets = [15, 30, 60, 120, 180, 360]

        let slotID: UUID
        var start: Date
        var end: Date
        var category: ActivityCategory?
        var visibility: AvailabilityVisibility = .privateUntilAccepted
        /// Clock reading used for validation; refreshed on every action.
        var now: Date
        var calendar: Calendar
        /// Snapshot of own slots when the sheet opened, used for the inline overlap check.
        var existing: [AvailabilitySlot]
        var isSaving = false
        var saveError: String?

        /// Opens the editor from a timeline position (or from "now" when `anchor` is nil).
        /// Returns nil when no 15-minute slot fits in the 14-day window.
        init?(
            anchor: Date?,
            now: Date,
            calendar: Calendar,
            existing: [AvailabilitySlot],
            slotID: UUID
        ) {
            guard let draft = AvailabilityPolicy.draftInterval(anchor: anchor, now: now, calendar: calendar) else {
                return nil
            }
            self.slotID = slotID
            self.start = draft.start
            self.end = draft.end
            self.category = nil
            self.visibility = .privateUntilAccepted
            self.now = now
            self.calendar = calendar
            self.existing = existing
        }

        /// Opens the editor with exactly the range picked on the timeline ("詳細を調整").
        /// The range is kept as-is, even when it is invalid, so the reason is shown next to it.
        init(
            range: QuarterRange,
            now: Date,
            calendar: Calendar,
            existing: [AvailabilitySlot],
            slotID: UUID
        ) {
            self.slotID = slotID
            self.start = range.start
            self.end = range.end
            self.category = nil
            self.visibility = .privateUntilAccepted
            self.now = now
            self.calendar = calendar
            self.existing = existing
        }

        var earliestStart: Date { AvailabilityPolicy.nextQuarterHour(after: now, calendar: calendar) }
        var latestEnd: Date { AvailabilityPolicy.latestEnd(now: now, calendar: calendar) }
        var duration: TimeInterval { end.timeIntervalSince(start) }
        var isOvernight: Bool { AvailabilityFormatting.isOvernight(start: start, end: end, calendar: calendar) }

        var slot: AvailabilitySlot {
            AvailabilitySlot(
                id: slotID,
                interval: TimeIntervalRange(id: slotID, start: start, end: end),
                category: category,
                visibility: visibility
            )
        }

        var issue: AvailabilityValidationError? {
            do {
                try AvailabilityPolicy.validate(slot, now: now, existing: existing, calendar: calendar)
                return nil
            } catch let error as AvailabilityValidationError {
                return error
            } catch {
                return .invalidInterval
            }
        }

        var canSave: Bool { issue == nil && !isSaving }

        var canMoveStartEarlier: Bool { start.addingTimeInterval(-AvailabilityPolicy.quarterHour) >= earliestStart }
        var canMoveStartLater: Bool { start.addingTimeInterval(2 * AvailabilityPolicy.quarterHour) <= latestEnd }
        var canMoveEndEarlier: Bool { end.addingTimeInterval(-AvailabilityPolicy.quarterHour) > start }
        var canMoveEndLater: Bool { end.addingTimeInterval(AvailabilityPolicy.quarterHour) <= latestEnd }

        func isPresetAvailable(minutes: Int) -> Bool {
            start.addingTimeInterval(TimeInterval(minutes * 60)) <= latestEnd
        }

        /// Moves the start while keeping the duration; the end is trimmed at the window end.
        mutating func moveStart(to proposed: Date) {
            let quarter = AvailabilityPolicy.quarterHour
            let floored = AvailabilityPolicy.floorToQuarterHour(proposed, calendar: calendar)
            let upper = latestEnd.addingTimeInterval(-quarter)
            let newStart = min(max(floored, earliestStart), upper)
            let keptDuration = max(duration, quarter)
            start = newStart
            end = min(newStart.addingTimeInterval(keptDuration), latestEnd)
        }

        mutating func moveEnd(to proposed: Date) {
            let quarter = AvailabilityPolicy.quarterHour
            let floored = AvailabilityPolicy.floorToQuarterHour(proposed, calendar: calendar)
            end = min(max(floored, start.addingTimeInterval(quarter)), latestEnd)
        }
    }

    enum Action: Equatable {
        case startStepped(quarters: Int)
        case endStepped(quarters: Int)
        case startPicked(Date)
        case endPicked(Date)
        case presetTapped(minutes: Int)
        case snapToEarliestTapped
        case categoryChanged(ActivityCategory?)
        case visibilityChanged(AvailabilityVisibility)
        case conflictTapped(UUID)
        case saveTapped
        case saveSucceeded(AppSnapshot)
        case saveFailed(String)
        case closeTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case saved(AppSnapshot)
            case showExistingSlot(UUID)
        }
    }

    @Dependency(\.date.now) var now
    @Dependency(\.himatchClient) var client
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .saveSucceeded, .saveFailed, .delegate:
                break
            default:
                state.now = now
            }

            switch action {
            case let .startStepped(quarters):
                state.moveStart(to: state.start.addingTimeInterval(Double(quarters) * AvailabilityPolicy.quarterHour))
                state.saveError = nil
                return .none

            case let .endStepped(quarters):
                state.moveEnd(to: state.end.addingTimeInterval(Double(quarters) * AvailabilityPolicy.quarterHour))
                state.saveError = nil
                return .none

            case let .startPicked(date):
                state.moveStart(to: date)
                state.saveError = nil
                return .none

            case let .endPicked(date):
                state.moveEnd(to: date)
                state.saveError = nil
                return .none

            case let .presetTapped(minutes):
                guard minutes > 0, state.isPresetAvailable(minutes: minutes) else { return .none }
                state.end = state.start.addingTimeInterval(TimeInterval(minutes * 60))
                state.saveError = nil
                return .none

            case .snapToEarliestTapped:
                state.moveStart(to: state.earliestStart)
                state.saveError = nil
                return .none

            case let .categoryChanged(category):
                state.category = category
                return .none

            case let .visibilityChanged(visibility):
                state.visibility = visibility
                return .none

            case let .conflictTapped(id):
                return .send(.delegate(.showExistingSlot(id)))

            case .saveTapped:
                guard state.canSave else { return .none }
                state.isSaving = true
                state.saveError = nil
                let slot = state.slot
                return .run { send in
                    do {
                        await send(.saveSucceeded(try await client.addAvailability(slot)))
                    } catch let error as AvailabilityValidationError {
                        await send(.saveFailed(error.message))
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }

            case let .saveSucceeded(snapshot):
                state.isSaving = false
                return .send(.delegate(.saved(snapshot)))

            case let .saveFailed(message):
                state.isSaving = false
                state.saveError = message
                return .none

            case .closeTapped:
                return .run { _ in await dismiss() }

            case .delegate:
                return .none
            }
        }
    }
}
