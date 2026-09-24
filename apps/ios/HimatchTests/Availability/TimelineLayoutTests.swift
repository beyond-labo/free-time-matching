import Foundation
import Testing
@testable import Himatch

@Suite("Timeline layout and formatting")
struct TimelineLayoutTests {
    private let calendar = AvailabilityTestClock.calendar

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        AvailabilityTestClock.date(day: day, hour: hour, minute: minute)
    }

    private func item(
        _ id: HomeTimelineFeature.State.Item,
        _ start: Date,
        _ end: Date,
        kind: HomeScheduleItem.Kind = .availability(.privateUntilAccepted)
    ) -> HomeScheduleItem {
        HomeScheduleItem(
            id: id,
            interval: TimeIntervalRange(start: start, end: end),
            title: "暇",
            systemImage: "clock.fill",
            kind: kind
        )
    }

    @Test("日付をまたぐ枠は日ごとに切り分けて表示する")
    func overnightItemIsClippedPerDay() {
        let overnight = item(.availability(UUID()), date(3, 22, 0), date(4, 1, 30))

        let first = TimelineLayout.segments(for: [overnight], on: date(3, 12, 0), calendar: calendar)
        let second = TimelineLayout.segments(for: [overnight], on: date(4, 12, 0), calendar: calendar)
        let third = TimelineLayout.segments(for: [overnight], on: date(5, 12, 0), calendar: calendar)

        #expect(first.map(\.start) == [date(3, 22, 0)])
        #expect(first.map(\.end) == [date(4, 0, 0)])
        #expect(first.first?.continuesToNextDay == true)
        #expect(second.map(\.start) == [date(4, 0, 0)])
        #expect(second.map(\.end) == [date(4, 1, 30)])
        #expect(second.first?.continuesFromPreviousDay == true)
        #expect(third.isEmpty)
    }

    @Test("0時ちょうどに終わる枠は翌日に表示しない（半開区間）")
    func itemEndingAtMidnightStaysOnItsDay() {
        let evening = item(.availability(UUID()), date(3, 22, 0), date(4, 0, 0))

        #expect(TimelineLayout.segments(for: [evening], on: date(4, 12, 0), calendar: calendar).isEmpty)
    }

    @Test("重なる暇と予定は横に並べ、重ならない枠は全幅")
    func overlappingItemsGetLanes() {
        let availability = item(.availability(UUID()), date(3, 10, 0), date(3, 12, 0))
        let plan = item(.plan(UUID()), date(3, 11, 0), date(3, 13, 0), kind: .plan)
        let later = item(.availability(UUID()), date(3, 14, 0), date(3, 15, 0))

        let segments = TimelineLayout.segments(for: [later, plan, availability], on: date(3, 0, 0), calendar: calendar)

        #expect(segments.map(\.id) == [availability.id, plan.id, later.id])
        #expect(segments.map(\.lane) == [0, 1, 0])
        #expect(segments.map(\.laneCount) == [2, 2, 1])
    }

    @Test("行内のタップ位置を15分に変換する")
    func tapOffsetMapsToQuarter() {
        #expect(TimelineLayout.quarter(forRowOffset: 0, hourHeight: 60) == 0)
        #expect(TimelineLayout.quarter(forRowOffset: 14.9, hourHeight: 60) == 0)
        #expect(TimelineLayout.quarter(forRowOffset: 15, hourHeight: 60) == 1)
        #expect(TimelineLayout.quarter(forRowOffset: 44, hourHeight: 60) == 2)
        #expect(TimelineLayout.quarter(forRowOffset: 59.9, hourHeight: 60) == 3)
        #expect(TimelineLayout.quarter(forRowOffset: 80, hourHeight: 60) == 3)
        #expect(TimelineLayout.quarter(forRowOffset: -5, hourHeight: 60) == 0)
        #expect(TimelineLayout.date(hour: 22, quarter: 3, on: date(3, 5, 0), calendar: calendar) == date(3, 22, 45))
    }

    @Test("時刻を縦位置へ変換する")
    func yOffset() {
        #expect(TimelineLayout.yOffset(for: date(3, 10, 30), dayStart: date(3, 0, 0), hourHeight: 60) == 630)
    }

    @Test("長さと範囲の表示")
    func formatting() {
        #expect(AvailabilityFormatting.duration(15 * 60) == "15分")
        #expect(AvailabilityFormatting.duration(2 * 60 * 60) == "2時間")
        #expect(AvailabilityFormatting.duration(3.5 * 60 * 60) == "3時間30分")
        #expect(
            AvailabilityFormatting.range(TimeIntervalRange(start: date(3, 22, 0), end: date(4, 1, 30)), calendar: calendar)
                == "9月3日(木) 22:00〜翌1:30"
        )
        #expect(
            AvailabilityFormatting.range(TimeIntervalRange(start: date(3, 10, 0), end: date(3, 12, 15)), calendar: calendar)
                == "9月3日(木) 10:00〜12:15"
        )
        #expect(AvailabilityFormatting.isOvernight(start: date(3, 22, 0), end: date(4, 0, 15), calendar: calendar))
        #expect(!AvailabilityFormatting.isOvernight(start: date(3, 22, 0), end: date(4, 0, 0), calendar: calendar))
        #expect(AvailabilityFormatting.timeZone(calendar, at: date(3, 10, 0)).hasSuffix("（GMT+9）"))
    }
}
