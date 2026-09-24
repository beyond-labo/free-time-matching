import Foundation
import Testing
@testable import Himatch

@Suite("Timeline direct selection rules")
struct TimelineSelectionTests {
    private let calendar = AvailabilityTestClock.calendar

    private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        AvailabilityTestClock.date(day: day, hour: hour, minute: minute, second: second)
    }

    @Test("タップ位置を含む15分を選ぶ")
    func quarterContainingTap() {
        let range = TimelineSelection.quarter(containing: date(3, 10, 7, 30), day: date(3, 0, 0), calendar: calendar)

        #expect(range == QuarterRange(start: date(3, 10, 0), end: date(3, 10, 15)))
        #expect(range.duration == 15 * 60)
    }

    @Test("日の最後の15分は翌0時で終わる")
    func lastQuarterOfDay() {
        let range = TimelineSelection.quarter(containing: date(3, 23, 50), day: date(3, 0, 0), calendar: calendar)

        #expect(range == QuarterRange(start: date(3, 23, 45), end: date(4, 0, 0)))
    }

    @Test("上下どちらのドラッグも開始が終了より前になる")
    func normalizationIsDirectionIndependent() {
        let down = TimelineSelection.normalized(anchor: date(3, 10, 7), focus: date(3, 11, 20), day: date(3, 0, 0), calendar: calendar)
        let up = TimelineSelection.normalized(anchor: date(3, 11, 20), focus: date(3, 10, 7), day: date(3, 0, 0), calendar: calendar)
        let still = TimelineSelection.normalized(anchor: date(3, 10, 7), focus: date(3, 10, 14), day: date(3, 0, 0), calendar: calendar)

        #expect(down == QuarterRange(start: date(3, 10, 0), end: date(3, 11, 30)))
        #expect(up == down)
        #expect(still == QuarterRange(start: date(3, 10, 0), end: date(3, 10, 15)))
    }

    @Test("日の外へのドラッグは0時と翌0時で止まる")
    func normalizationClampsToDay() {
        let intoNextDay = TimelineSelection.normalized(anchor: date(3, 22, 0), focus: date(4, 3, 0), day: date(3, 0, 0), calendar: calendar)
        let intoPreviousDay = TimelineSelection.normalized(anchor: date(3, 1, 0), focus: date(2, 20, 0), day: date(3, 0, 0), calendar: calendar)

        #expect(intoNextDay == QuarterRange(start: date(3, 22, 0), end: date(4, 0, 0)))
        #expect(intoPreviousDay == QuarterRange(start: date(3, 0, 0), end: date(3, 1, 15)))
    }

    @Test("15分単位の拡張・縮小は最低15分と日境界を守る")
    func steppingBounds() {
        let base = QuarterRange(start: date(3, 23, 30), end: date(3, 23, 45))

        #expect(TimelineSelection.stepped(base, edge: .end, quarters: 3, calendar: calendar).end == date(4, 0, 0))
        #expect(TimelineSelection.stepped(base, edge: .end, quarters: -1, calendar: calendar) == base)
        #expect(TimelineSelection.stepped(base, edge: .start, quarters: 1, calendar: calendar) == base)
        #expect(TimelineSelection.stepped(base, edge: .start, quarters: -2, calendar: calendar).start == date(3, 23, 0))
    }

    @Test("ハンドルは最寄りの15分境界へ合わせ、反対側を越えない")
    func handleDragRounding() {
        let base = QuarterRange(start: date(3, 10, 0), end: date(3, 11, 0))

        #expect(TimelineSelection.dragged(base, edge: .end, to: date(3, 11, 7), calendar: calendar).end == date(3, 11, 0))
        #expect(TimelineSelection.dragged(base, edge: .end, to: date(3, 11, 8), calendar: calendar).end == date(3, 11, 15))
        #expect(TimelineSelection.dragged(base, edge: .end, to: date(3, 8, 0), calendar: calendar).end == date(3, 10, 15))
        #expect(TimelineSelection.dragged(base, edge: .start, to: date(3, 12, 0), calendar: calendar).start == date(3, 10, 45))
    }

    @Test("縦位置と時刻を相互に変換する")
    func yPositionRoundTrip() {
        let dayStart = date(3, 0, 0)
        let y = TimelineLayout.yOffset(for: date(3, 10, 30), dayStart: dayStart, hourHeight: 60)

        #expect(TimelineLayout.date(atY: y, dayStart: dayStart, hourHeight: 60) == date(3, 10, 30))
        #expect(TimelineLayout.date(atY: 15, dayStart: dayStart, hourHeight: 60) == date(3, 0, 15))
    }

    @Test("長押しの成立位置をアンカーとし、静止したまま離しても15分を選び、上下どちらへも範囲を伸ばす")
    func pressTrackerAnchorsAtRecognition() {
        var tracker = TimelinePressTracker()
        #expect(tracker.moved(to: 300) == nil)
        #expect(!tracker.isPressing)

        let began = tracker.began(at: 600)
        #expect(began.anchorY == 600 && began.focusY == 600)
        #expect(tracker.isPressing)

        let down = tracker.moved(to: 690)
        #expect(down?.anchorY == 600 && down?.focusY == 690)
        let up = tracker.moved(to: 540)
        #expect(up?.anchorY == 600 && up?.focusY == 540)

        tracker.ended()
        #expect(!tracker.isPressing)
        #expect(tracker.moved(to: 700) == nil)
    }

    @Test("長押し位置の縦座標は15分へ正規化される")
    func pressPositionsMapToQuarterRange() {
        let dayStart = date(3, 0, 0)
        let anchor = TimelineLayout.date(atY: 607, dayStart: dayStart, hourHeight: 60)   // 10:07
        let focus = TimelineLayout.date(atY: 680, dayStart: dayStart, hourHeight: 60)    // 11:20

        #expect(
            TimelineSelection.normalized(anchor: anchor, focus: focus, day: dayStart, calendar: calendar)
                == QuarterRange(start: date(3, 10, 0), end: date(3, 11, 30))
        )
        #expect(
            TimelineSelection.normalized(anchor: anchor, focus: anchor, day: dayStart, calendar: calendar)
                == QuarterRange(start: date(3, 10, 0), end: date(3, 10, 15))
        )
    }

    @Test("範囲選択は0.25〜0.35秒の長押し成立後で、成立前に10pt以上動けばスクロールに譲る")
    @MainActor
    func longPressThresholds() {
        #expect(TimelineDayView.longPressDuration >= 0.25 && TimelineDayView.longPressDuration <= 0.35)
        #expect(TimelineDayView.longPressMaximumDistance <= 10)
    }
}
