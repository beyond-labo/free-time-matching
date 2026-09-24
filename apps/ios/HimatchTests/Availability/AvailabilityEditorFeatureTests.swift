import ComposableArchitecture
import Foundation
import Testing
@testable import Himatch

@MainActor
@Suite("Availability editor")
struct AvailabilityEditorFeatureTests {
    private let calendar = AvailabilityTestClock.calendar
    private let now = AvailabilityTestClock.now
    private let slotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        AvailabilityTestClock.date(day: day, hour: hour, minute: minute, second: second)
    }

    private func editor(anchor: Date?, existing: [AvailabilitySlot] = []) -> AvailabilityEditorFeature.State {
        AvailabilityEditorFeature.State(
            anchor: anchor,
            now: now,
            calendar: calendar,
            existing: existing,
            slotID: slotID
        )!
    }

    private func makeStore(
        _ state: AvailabilityEditorFeature.State,
        client: HimatchClient = .productionPlaceholder
    ) -> TestStoreOf<AvailabilityEditorFeature> {
        TestStore(initialState: state) {
            AvailabilityEditorFeature()
        } withDependencies: {
            $0.date.now = AvailabilityTestClock.now
            $0.himatchClient = client
        }
    }

    @Test("時間軸から開いた初期値は15分境界・2時間・未選択・非公開")
    func initialValuesFromTimeline() {
        let state = editor(anchor: date(3, 22, 7, 40))

        #expect(state.start == date(3, 22, 0))
        #expect(state.end == date(4, 0, 0))
        #expect(state.duration == 2 * 60 * 60)
        #expect(state.category == nil)
        #expect(state.visibility == .privateUntilAccepted)
        #expect(state.issue == nil)
        #expect(state.isOvernight == false)
    }

    @Test("常設ボタンからは次の15分境界を開始にする")
    func initialValuesFromNow() {
        let state = editor(anchor: nil)

        #expect(state.start == date(1, 10, 15))
        #expect(state.end == date(1, 12, 15))
    }

    @Test("カレンダーで選んだ範囲は2時間初期値に戻さずそのまま編集する")
    func selectedRangeIsKept() {
        let state = AvailabilityEditorFeature.State(
            range: QuarterRange(start: date(3, 10, 0), end: date(3, 10, 45)),
            now: now,
            calendar: calendar,
            existing: [],
            slotID: slotID
        )

        #expect(state.start == date(3, 10, 0))
        #expect(state.end == date(3, 10, 45))
        #expect(state.category == nil)
        #expect(state.visibility == .privateUntilAccepted)
        #expect(state.issue == nil)

        let past = AvailabilityEditorFeature.State(
            range: QuarterRange(start: date(1, 9, 0), end: date(1, 9, 15)),
            now: now,
            calendar: calendar,
            existing: [],
            slotID: slotID
        )
        #expect(past.start == date(1, 9, 0))
        #expect(past.issue == .past)
    }

    @Test("14日範囲に15分も残らない位置からは開始しない")
    func cannotOpenOutsideWindow() {
        let state = AvailabilityEditorFeature.State(
            anchor: date(15, 10, 0),
            now: now,
            calendar: calendar,
            existing: [],
            slotID: slotID
        )

        #expect(state == nil)
    }

    @Test("終了を15分刻みで調整し、開始から15分より短くしない")
    func endStepsByQuarterHour() async {
        let store = makeStore(editor(anchor: date(3, 22, 0)))

        await store.send(.endStepped(quarters: 1)) {
            $0.end = self.date(4, 0, 15)
        }
        await store.send(.endStepped(quarters: -3)) {
            $0.end = self.date(3, 23, 30)
        }
        await store.send(.endStepped(quarters: -20)) {
            $0.end = self.date(3, 22, 15)
        }
        #expect(store.state.duration == 15 * 60)
        #expect(store.state.issue == nil)
        #expect(!store.state.canMoveEndEarlier)
    }

    @Test("開始を動かすと長さを保ち、現在より前には戻せない")
    func startStepsKeepDuration() async {
        let store = makeStore(editor(anchor: date(3, 22, 0)))

        await store.send(.startStepped(quarters: 1)) {
            $0.start = self.date(3, 22, 15)
            $0.end = self.date(4, 0, 15)
        }
        await store.send(.startStepped(quarters: -1000)) {
            $0.start = self.date(1, 10, 15)
            $0.end = self.date(1, 12, 15)
        }
        #expect(!store.state.canMoveStartEarlier)
    }

    @Test("日時ピッカーの値は15分境界へ切り下げる")
    func pickedDatesAreFloored() async {
        let store = makeStore(editor(anchor: date(3, 22, 0)))

        await store.send(.startPicked(date(4, 13, 52, 10))) {
            $0.start = self.date(4, 13, 45)
            $0.end = self.date(4, 15, 45)
        }
        await store.send(.endPicked(date(4, 18, 29))) {
            $0.end = self.date(4, 18, 15)
        }
        await store.send(.endPicked(date(4, 12, 0))) {
            $0.end = self.date(4, 14, 0)
        }
    }

    @Test("長さプリセットで15分から日付またぎまで設定できる")
    func durationPresets() async {
        let store = makeStore(editor(anchor: date(3, 22, 0)))

        await store.send(.presetTapped(minutes: 15)) {
            $0.end = self.date(3, 22, 15)
        }
        await store.send(.presetTapped(minutes: 360)) {
            $0.end = self.date(4, 4, 0)
        }
        #expect(store.state.isOvernight)
        #expect(store.state.issue == nil)
        #expect(AvailabilityFormatting.duration(store.state.duration) == "6時間")
    }

    @Test("14日範囲を超えるプリセットと調整は無効")
    func windowEndClampsAdjustments() async {
        let store = makeStore(editor(anchor: date(15, 9, 0)))
        #expect(store.state.end == date(15, 10, 0))
        #expect(!store.state.isPresetAvailable(minutes: 120))
        #expect(store.state.isPresetAvailable(minutes: 60))

        await store.send(.presetTapped(minutes: 120))
        await store.send(.endStepped(quarters: 1))
        await store.send(.startStepped(quarters: 4)) {
            $0.start = self.date(15, 9, 45)
            $0.end = self.date(15, 10, 0)
        }
        #expect(!store.state.canMoveEndLater)
    }

    @Test("重複する枠は保存せず、既存枠への誘導を通知する")
    func overlapBlocksSaveAndPointsToExistingSlot() async {
        let existing = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(3, 21, 0), end: date(3, 23, 0))
        )
        var client = HimatchClient.productionPlaceholder
        client.addAvailability = { _ in
            Issue.record("重複時はclientを呼ばない")
            return .empty()
        }
        let store = makeStore(editor(anchor: date(3, 22, 0), existing: [existing]), client: client)
        #expect(store.state.issue == .overlap(existing.id))
        #expect(!store.state.canSave)

        await store.send(.saveTapped)
        await store.send(.conflictTapped(existing.id))
        await store.receive(.delegate(.showExistingSlot(existing.id)))
    }

    @Test("既存枠の終了から始まる枠は保存できる（半開区間）")
    func adjacentSlotCanBeSaved() {
        let existing = AvailabilitySlot(
            interval: TimeIntervalRange(start: date(3, 20, 0), end: date(3, 22, 0))
        )
        let state = editor(anchor: date(3, 22, 0), existing: [existing])

        #expect(state.issue == nil)
    }

    @Test("保存すると入力どおりの非公開枠を送信し、結果を親へ渡す")
    func saveSendsSlotAndDelegates() async {
        let saved = LockIsolated<AvailabilitySlot?>(nil)
        var client = HimatchClient.productionPlaceholder
        client.addAvailability = { slot in
            saved.setValue(slot)
            var snapshot = AppSnapshot.empty(profileName: "ひまり")
            snapshot.availability = [slot]
            return snapshot
        }
        let store = makeStore(editor(anchor: date(3, 22, 0)), client: client)

        await store.send(.categoryChanged(.game)) {
            $0.category = .game
        }
        var expected = AppSnapshot.empty(profileName: "ひまり")
        expected.availability = [store.state.slot]
        await store.send(.saveTapped) {
            $0.isSaving = true
        }
        await store.receive(.saveSucceeded(expected)) {
            $0.isSaving = false
        }
        await store.receive(.delegate(.saved(expected)))

        #expect(saved.value?.id == slotID)
        #expect(saved.value?.interval.start == date(3, 22, 0))
        #expect(saved.value?.interval.end == date(4, 0, 0))
        #expect(saved.value?.category == .game)
        #expect(saved.value?.visibility == .privateUntilAccepted)
    }

    @Test("保存に失敗しても入力を保持し、理由を表示する")
    func saveFailureKeepsInput() async {
        var client = HimatchClient.productionPlaceholder
        client.addAvailability = { _ in throw AvailabilityValidationError.outsideWindow }
        let store = makeStore(editor(anchor: date(3, 22, 0)), client: client)

        await store.send(.visibilityChanged(.shareOnHosting)) {
            $0.visibility = .shareOnHosting
        }
        await store.send(.saveTapped) {
            $0.isSaving = true
        }
        await store.receive(.saveFailed(AvailabilityValidationError.outsideWindow.message)) {
            $0.isSaving = false
            $0.saveError = AvailabilityValidationError.outsideWindow.message
        }
        #expect(store.state.start == date(3, 22, 0))
        #expect(store.state.end == date(4, 0, 0))
        #expect(store.state.visibility == .shareOnHosting)
    }

    @Test("保存前に開始時刻を過ぎた場合は送信せず、次の15分へ合わせられる")
    func staleStartIsRevalidatedBeforeSave() async {
        var client = HimatchClient.productionPlaceholder
        client.addAvailability = { _ in
            Issue.record("過去の開始はclientへ送らない")
            return .empty()
        }
        let store = makeStore(editor(anchor: nil), client: client)
        let later = date(1, 10, 20)
        store.dependencies.date = .constant(later)

        await store.send(.saveTapped) {
            $0.now = later
        }
        #expect(store.state.issue == .past)

        await store.send(.snapToEarliestTapped) {
            $0.start = self.date(1, 10, 30)
            $0.end = self.date(1, 12, 30)
        }
        #expect(store.state.issue == nil)
    }
}
