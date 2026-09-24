import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("Home timeline")
struct HomeTimelineFeatureTests {
    private let calendar = AvailabilityTestClock.calendar

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        AvailabilityTestClock.date(day: day, hour: hour, minute: minute)
    }

    private func range(_ day: Int, _ startHour: Int, _ startMinute: Int, _ endDay: Int, _ endHour: Int, _ endMinute: Int) -> QuarterRange {
        QuarterRange(start: date(day, startHour, startMinute), end: date(endDay, endHour, endMinute))
    }

    private func state(dayIndex: Int = 0, selection: QuarterRange? = nil) -> HomeTimelineFeature.State {
        var state = HomeTimelineFeature.State()
        state.today = date(1, 0, 0)
        state.selectedDayIndex = dayIndex
        state.selection = selection.map { HomeTimelineFeature.State.Selection(range: $0) }
        return state
    }

    private func makeStore(
        _ state: HomeTimelineFeature.State = HomeTimelineFeature.State(),
        now: Date = AvailabilityTestClock.now
    ) -> TestStoreOf<HomeTimelineFeature> {
        TestStore(initialState: state) {
            HomeTimelineFeature()
        } withDependencies: {
            $0.date.now = now
            $0.calendar = AvailabilityTestClock.calendar
        }
    }

    // MARK: Window and navigation

    @Test("表示範囲は今日の0時から始まる14日")
    func refreshWindowAnchorsToday() async {
        let store = makeStore()

        await store.send(.refreshWindow) {
            $0.today = self.date(1, 0, 0)
        }
        #expect(store.state.day(at: 13, calendar: calendar) == date(14, 0, 0))
    }

    @Test("日表示の移動は今日から13日後までに収まる")
    func dayNavigationIsClamped() async {
        let store = makeStore(state())

        await store.send(.previousTapped)
        await store.send(.nextTapped) { $0.selectedDayIndex = 1 }
        await store.send(.daySelected(20)) { $0.selectedDayIndex = 13 }
        #expect(!store.state.canGoForward)
        await store.send(.nextTapped)
        await store.send(.todayTapped) { $0.selectedDayIndex = 0 }
        #expect(!store.state.canGoBackward)
    }

    @Test("週表示は今日からの7日と次の7日を切り替える")
    func weekNavigation() async {
        let store = makeStore(state(dayIndex: 3))

        await store.send(.modeChanged(.week)) { $0.mode = .week }
        #expect(store.state.weekDayIndices == 0..<7)
        await store.send(.nextTapped) { $0.selectedDayIndex = 10 }
        #expect(store.state.weekDayIndices == 7..<14)
        #expect(!store.state.canGoForward)
        await store.send(.previousTapped) { $0.selectedDayIndex = 3 }
        await store.send(.modeChanged(.day)) { $0.mode = .day }
    }

    @Test("日付が変わったら同じ日を選んだまま表示範囲を進める")
    func refreshWindowAfterMidnightKeepsSelectedDate() async {
        let store = makeStore(state(dayIndex: 3, selection: range(4, 10, 0, 4, 10, 15)), now: date(2, 0, 30))

        await store.send(.refreshWindow) {
            $0.today = self.date(2, 0, 0)
            $0.selectedDayIndex = 2
        }
        #expect(store.state.selection?.range == range(4, 10, 0, 4, 10, 15))
    }

    // MARK: Direct selection

    @Test("タップはその15分を選択し、エディタを開かない")
    func tapSelectsQuarterHour() async {
        let store = makeStore(state(dayIndex: 2))

        await store.send(.quarterTapped(date(3, 10, 7))) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 10, 15))
        }
        await store.send(.quarterTapped(date(3, 14, 50))) {
            $0.selection = .init(range: self.range(3, 14, 45, 3, 15, 0))
        }
    }

    @Test("長押しだけで離した場合も15分を選択する")
    func pressWithoutDragSelectsQuarterHour() async {
        let store = makeStore(state(dayIndex: 2))

        await store.send(.rangeSelectionChanged(anchor: date(3, 9, 30), focus: date(3, 9, 30))) {
            $0.selection = .init(range: self.range(3, 9, 30, 3, 9, 45))
        }
    }

    @Test("下方向と上方向のドラッグは同じ範囲に正規化する")
    func dragDirectionIsNormalized() async {
        let store = makeStore(state(dayIndex: 2))

        await store.send(.rangeSelectionChanged(anchor: date(3, 10, 7), focus: date(3, 11, 20))) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 11, 30))
        }
        // Same drag continuing: an unchanged 15-minute range does not reset the selection.
        await store.send(.rangeSelectionChanged(anchor: date(3, 10, 7), focus: date(3, 11, 29)))
        await store.send(.selectionCleared) { $0.selection = nil }
        await store.send(.rangeSelectionChanged(anchor: date(3, 11, 20), focus: date(3, 10, 7))) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 11, 30))
        }
    }

    @Test("選択は表示中の1日に収め、日付をまたがない")
    func selectionIsClampedToDay() async {
        let store = makeStore(state(dayIndex: 2))

        await store.send(.rangeSelectionChanged(anchor: date(3, 23, 10), focus: date(4, 0, 40))) {
            $0.selection = .init(range: self.range(3, 23, 0, 4, 0, 0))
        }
        await store.send(.rangeSelectionChanged(anchor: date(3, 0, 20), focus: date(2, 23, 0))) {
            $0.selection = .init(range: self.range(3, 0, 0, 3, 0, 30))
        }
    }

    @Test("開始・終了の15分拡張と縮小（VoiceOver代替操作）は最低15分と日境界を守る")
    func edgeSteppingKeepsMinimumAndDayBounds() async {
        let store = makeStore(state(dayIndex: 2, selection: range(3, 10, 0, 3, 10, 15)))

        await store.send(.selectionEdgeStepped(.end, quarters: 2)) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 10, 45))
        }
        await store.send(.selectionEdgeStepped(.end, quarters: -10)) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 10, 15))
        }
        await store.send(.selectionEdgeStepped(.start, quarters: -1)) {
            $0.selection = .init(range: self.range(3, 9, 45, 3, 10, 15))
        }
        await store.send(.selectionEdgeStepped(.start, quarters: 5)) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 10, 15))
        }
        await store.send(.selectionEdgeStepped(.start, quarters: -1000)) {
            $0.selection = .init(range: self.range(3, 0, 0, 3, 10, 15))
        }
    }

    @Test("ハンドルのドラッグは最寄りの15分へ合わせる")
    func handleDragSnapsToNearestQuarter() async {
        let store = makeStore(state(dayIndex: 2, selection: range(3, 10, 0, 3, 11, 0)))

        await store.send(.selectionEdgeDragged(.end, to: date(3, 11, 38))) {
            $0.selection = .init(range: self.range(3, 10, 0, 3, 11, 45))
        }
        await store.send(.selectionEdgeDragged(.start, to: date(3, 9, 7))) {
            $0.selection = .init(range: self.range(3, 9, 0, 3, 11, 45))
        }
        await store.send(.selectionEdgeDragged(.start, to: date(3, 13, 0))) {
            $0.selection = .init(range: self.range(3, 11, 30, 3, 11, 45))
        }
    }

    @Test("週表示の時刻タップは該当日の日表示へ移り15分を選択する")
    func weekTapOpensDayWithSelection() async {
        var initial = state(dayIndex: 0)
        initial.mode = .week
        let store = makeStore(initial)

        await store.send(.quarterTapped(date(5, 18, 0))) {
            $0.mode = .day
            $0.selectedDayIndex = 4
            $0.selection = .init(range: self.range(5, 18, 0, 5, 18, 15))
        }
    }

    @Test("日の移動と週表示への切替で選択を解除する")
    func navigationClearsSelection() async {
        let store = makeStore(state(dayIndex: 2, selection: range(3, 10, 0, 3, 10, 15)))

        await store.send(.daySelected(2))
        #expect(store.state.selection != nil)
        await store.send(.nextTapped) {
            $0.selectedDayIndex = 3
            $0.selection = nil
        }
        await store.send(.quarterTapped(date(4, 12, 0))) {
            $0.selection = .init(range: self.range(4, 12, 0, 4, 12, 15))
        }
        await store.send(.modeChanged(.week)) {
            $0.mode = .week
            $0.selection = nil
        }
    }

    // MARK: Confirmation

    @Test("登録できない理由がある選択は登録を依頼しない")
    func quickSaveRequiresValidSelection() async {
        var initial = state(dayIndex: 0, selection: range(1, 9, 0, 1, 9, 15))
        initial.selection?.issue = .past
        let store = makeStore(initial)

        await store.send(.quickSaveTapped)
    }

    @Test("有効な選択の登録と詳細調整は範囲をそのまま親へ渡す")
    func confirmationDelegatesExactRange() async {
        let picked = range(3, 10, 0, 3, 10, 45)
        let store = makeStore(state(dayIndex: 2, selection: picked))

        await store.send(.quickSaveTapped)
        await store.receive(.delegate(.quickSave(picked)))
        await store.send(.adjustDetailsTapped)
        await store.receive(.delegate(.adjustSelection(picked)))
    }

    @Test("登録中は選択・取消・日移動・再送を受け付けない")
    func savingLocksSelection() async {
        var initial = state(dayIndex: 2, selection: range(3, 10, 0, 3, 10, 45))
        initial.selection?.isSaving = true
        let store = makeStore(initial)

        await store.send(.quarterTapped(date(3, 15, 0)))
        await store.send(.selectionEdgeStepped(.end, quarters: 1))
        await store.send(.selectionCleared)
        await store.send(.nextTapped)
        await store.send(.quickSaveTapped)
        await store.send(.adjustDetailsTapped)
        #expect(!store.state.canGoForward)
    }

    @Test("常設ボタンは位置指定なしでエディタを開く")
    func newAvailabilityButton() async {
        let store = makeStore()

        await store.send(.newAvailabilityTapped)
        await store.receive(.delegate(.startAvailability(anchor: nil)))
    }

    @Test("枠の選択と削除確定")
    func selectAndDeleteItem() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let store = makeStore()

        await store.send(.itemTapped(.availability(id))) {
            $0.selectedItem = .availability(id)
        }
        await store.send(.deleteAvailabilityConfirmed(id)) {
            $0.selectedItem = nil
        }
        await store.receive(.delegate(.removeAvailability(id)))
    }

    @Test("指定日時の日と枠へフォーカスする")
    func focusSelectsDayAndItem() {
        let id = UUID()
        var state = HomeTimelineFeature.State()

        state.focus(on: date(5, 23, 0), item: .availability(id), now: AvailabilityTestClock.now, calendar: calendar)

        #expect(state.today == date(1, 0, 0))
        #expect(state.selectedDayIndex == 4)
        #expect(state.selectedItem == .availability(id))
    }
}
