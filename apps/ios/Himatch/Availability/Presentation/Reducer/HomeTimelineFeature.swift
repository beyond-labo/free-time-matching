import ComposableArchitecture
import Foundation

/// Home calendar: which of the next 14 days is shown, day/week mode, the selected item and the
/// directly picked 15-minute selection. Schedule data stays with the parent; the parent also
/// validates the selection with `AvailabilityPolicy` and owns the quick-save side effect.
@Reducer
struct HomeTimelineFeature {
    @ObservableState
    struct State: Equatable {
        enum Mode: String, CaseIterable, Equatable, Sendable {
            case day
            case week

            var title: String {
                switch self {
                case .day: "日"
                case .week: "週"
                }
            }
        }

        enum Item: Hashable, Sendable {
            case availability(UUID)
            case plan(UUID)
        }

        /// Range picked on the day grid, plus what the parent learned about it.
        struct Selection: Equatable, Sendable {
            var range: QuarterRange
            /// Why the range cannot be registered. Written by the parent from `AvailabilityPolicy.validate`.
            var issue: AvailabilityValidationError?
            var isSaving = false
            var saveError: String?

            init(range: QuarterRange) {
                self.range = range
            }

            var canQuickSave: Bool { issue == nil && !isSaving }
        }

        static let dayCount = 14
        static let daysPerWeek = 7

        var mode: Mode = .day
        /// Start of the first displayed day (today). Set by `refreshWindow`.
        var today: Date?
        var selectedDayIndex = 0
        var selectedItem: Item?
        var selection: Selection?
        /// The slot registered by the last quick save, marked on the grid until the next selection.
        var lastSavedItem: Item?
        var quickSaveSuccessCount = 0

        var isSavingSelection: Bool { selection?.isSaving == true }

        var weekPage: Int { selectedDayIndex / Self.daysPerWeek }
        var weekDayIndices: Range<Int> {
            let first = weekPage * Self.daysPerWeek
            return first..<min(first + Self.daysPerWeek, Self.dayCount)
        }

        var canGoBackward: Bool {
            guard !isSavingSelection else { return false }
            return mode == .day ? selectedDayIndex > 0 : weekPage > 0
        }

        var canGoForward: Bool {
            guard !isSavingSelection else { return false }
            return mode == .day
                ? selectedDayIndex < Self.dayCount - 1
                : weekPage < (Self.dayCount - 1) / Self.daysPerWeek
        }

        func day(at index: Int, calendar: Calendar) -> Date? {
            guard let today else { return nil }
            return calendar.date(byAdding: .day, value: index, to: today)
        }

        /// Selects the day containing `date` (when inside the window) and optionally an item.
        mutating func focus(on date: Date, item: Item?, now: Date, calendar: Calendar) {
            let today = self.today ?? calendar.startOfDay(for: now)
            self.today = today
            if let offset = dayOffset(of: date, today: today, calendar: calendar) {
                selectDay(offset)
            }
            selectedItem = item
        }

        fileprivate func dayOffset(of date: Date, today: Date, calendar: Calendar) -> Int? {
            let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
            return (0..<Self.dayCount).contains(offset) ? offset : nil
        }

        /// Changing the displayed day drops a selection that belongs to another day.
        fileprivate mutating func selectDay(_ index: Int) {
            let clamped = min(max(index, 0), Self.dayCount - 1)
            if clamped != selectedDayIndex { selection = nil }
            selectedDayIndex = clamped
        }
    }

    enum Action: Equatable {
        case refreshWindow
        case modeChanged(State.Mode)
        case daySelected(Int)
        case previousTapped
        case nextTapped
        case todayTapped
        /// Tap on the day grid (or a week cell / VoiceOver row action): select that quarter hour.
        case quarterTapped(Date)
        /// Long press + drag on the day grid. Dates are raw positions; the reducer snaps them.
        case rangeSelectionChanged(anchor: Date, focus: Date)
        case selectionEdgeStepped(SelectionEdge, quarters: Int)
        case selectionEdgeDragged(SelectionEdge, to: Date)
        case selectionCleared
        case quickSaveTapped
        case adjustDetailsTapped
        case newAvailabilityTapped
        case itemTapped(State.Item)
        case itemDismissed
        case deleteAvailabilityConfirmed(UUID)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// Open the editor from "now" (the persistent button; `anchor` nil = next quarter hour).
            case startAvailability(anchor: Date?)
            /// Register the selection as a private slot without category, after parent validation.
            case quickSave(QuarterRange)
            /// Open the editor with exactly this range.
            case adjustSelection(QuarterRange)
            case removeAvailability(UUID)
        }
    }

    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            // While a quick save is in flight the selection and the displayed day stay fixed.
            if state.isSavingSelection, Self.isBlockedWhileSaving(action) {
                return .none
            }

            switch action {
            case .refreshWindow:
                let newToday = calendar.startOfDay(for: now)
                if let oldToday = state.today, oldToday != newToday {
                    let shift = calendar.dateComponents([.day], from: oldToday, to: newToday).day ?? 0
                    state.selectedDayIndex = min(max(state.selectedDayIndex - shift, 0), State.dayCount - 1)
                }
                state.today = newToday
                if let selection = state.selection,
                   state.dayOffset(of: selection.range.start, today: newToday, calendar: calendar) != state.selectedDayIndex {
                    state.selection = nil
                }
                return .none

            case let .modeChanged(mode):
                state.mode = mode
                if mode == .week { state.selection = nil }
                return .none

            case let .daySelected(index):
                state.selectDay(index)
                return .none

            case .previousTapped:
                state.selectDay(state.selectedDayIndex - (state.mode == .day ? 1 : State.daysPerWeek))
                return .none

            case .nextTapped:
                state.selectDay(state.selectedDayIndex + (state.mode == .day ? 1 : State.daysPerWeek))
                return .none

            case .todayTapped:
                state.selectDay(0)
                return .none

            case let .quarterTapped(date):
                let today = state.today ?? calendar.startOfDay(for: now)
                state.today = today
                guard let offset = state.dayOffset(of: date, today: today, calendar: calendar) else { return .none }
                state.mode = .day
                state.selectDay(offset)
                state.select(TimelineSelection.quarter(containing: date, day: date, calendar: calendar))
                return .none

            case let .rangeSelectionChanged(anchor, focus):
                let today = state.today ?? calendar.startOfDay(for: now)
                state.today = today
                guard let offset = state.dayOffset(of: anchor, today: today, calendar: calendar) else { return .none }
                state.selectDay(offset)
                state.select(TimelineSelection.normalized(anchor: anchor, focus: focus, day: anchor, calendar: calendar))
                return .none

            case let .selectionEdgeStepped(edge, quarters):
                guard let selection = state.selection else { return .none }
                state.select(TimelineSelection.stepped(selection.range, edge: edge, quarters: quarters, calendar: calendar))
                return .none

            case let .selectionEdgeDragged(edge, date):
                guard let selection = state.selection else { return .none }
                state.select(TimelineSelection.dragged(selection.range, edge: edge, to: date, calendar: calendar))
                return .none

            case .selectionCleared:
                state.selection = nil
                return .none

            case .quickSaveTapped:
                guard let selection = state.selection, selection.canQuickSave else { return .none }
                return .send(.delegate(.quickSave(selection.range)))

            case .adjustDetailsTapped:
                guard let selection = state.selection else { return .none }
                return .send(.delegate(.adjustSelection(selection.range)))

            case .newAvailabilityTapped:
                return .send(.delegate(.startAvailability(anchor: nil)))

            case let .itemTapped(item):
                state.selectedItem = item
                return .none

            case .itemDismissed:
                state.selectedItem = nil
                return .none

            case let .deleteAvailabilityConfirmed(id):
                state.selectedItem = nil
                return .send(.delegate(.removeAvailability(id)))

            case .delegate:
                return .none
            }
        }
    }

    private static func isBlockedWhileSaving(_ action: Action) -> Bool {
        switch action {
        case .modeChanged, .daySelected, .previousTapped, .nextTapped, .todayTapped,
             .quarterTapped, .rangeSelectionChanged, .selectionEdgeStepped, .selectionEdgeDragged,
             .selectionCleared, .quickSaveTapped, .adjustDetailsTapped, .newAvailabilityTapped:
            return true
        case .refreshWindow, .itemTapped, .itemDismissed, .deleteAvailabilityConfirmed, .delegate:
            return false
        }
    }
}

private extension HomeTimelineFeature.State {
    /// Replaces the selection range. Unchanged ranges keep the parent's validation result.
    mutating func select(_ range: QuarterRange) {
        lastSavedItem = nil
        if selection?.range == range { return }
        selection = Selection(range: range)
    }
}
