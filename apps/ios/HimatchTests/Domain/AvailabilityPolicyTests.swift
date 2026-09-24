import Foundation
import Testing
@testable import Himatch

@Suite("Availability policy")
struct AvailabilityPolicyTests {
    @Test("隣接する時間枠は重複しない")
    func adjacentIntervalsDoNotOverlap() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let first = TimeIntervalRange(start: start, end: start.addingTimeInterval(3600))
        let second = TimeIntervalRange(start: first.end, end: first.end.addingTimeInterval(3600))

        #expect(!first.overlaps(second))
        #expect(first.intersection(second) == nil)
    }

    @Test("既存枠との重複を拒否する")
    func overlapIsRejected() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let start = AvailabilityPolicy.nextQuarterHour(after: now)
        let existing = AvailabilitySlot(interval: TimeIntervalRange(start: start, end: start.addingTimeInterval(7200)))
        let candidate = AvailabilitySlot(
            interval: TimeIntervalRange(
                start: start.addingTimeInterval(3600),
                end: start.addingTimeInterval(10_800)
            )
        )

        #expect(throws: AvailabilityValidationError.overlap(existing.id)) {
            try AvailabilityPolicy.validate(candidate, now: now, existing: [existing])
        }
    }

    @Test("次の15分境界は秒とナノ秒を持たない")
    func nextQuarterHourIsAStableBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let date = Date(timeIntervalSince1970: 2_000_000_000.75)
        let result = AvailabilityPolicy.nextQuarterHour(after: date, calendar: calendar)

        #expect(calendar.component(.minute, from: result) % 15 == 0)
        #expect(calendar.component(.second, from: result) == 0)
        #expect(calendar.component(.nanosecond, from: result) == 0)
    }

    @Test("新規の暇枠は非公開が初期値")
    func newAvailabilityDefaultsToPrivate() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let slot = AvailabilitySlot(interval: TimeIntervalRange(start: start, end: start.addingTimeInterval(7200)))

        #expect(slot.visibility == .privateUntilAccepted)
    }
}

@Suite("Availability policy: 15分境界と14日範囲")
struct AvailabilityQuarterHourPolicyTests {
    private let calendar = AvailabilityTestClock.calendar
    private let now = AvailabilityTestClock.now

    private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        AvailabilityTestClock.date(day: day, hour: hour, minute: minute, second: second)
    }

    private func slot(_ start: Date, _ end: Date) -> AvailabilitySlot {
        AvailabilitySlot(interval: TimeIntervalRange(start: start, end: end))
    }

    @Test("15分境界へ切り下げる")
    func floorsToQuarterHour() {
        #expect(AvailabilityPolicy.floorToQuarterHour(date(2, 10, 7, 30), calendar: calendar) == date(2, 10, 0))
        #expect(AvailabilityPolicy.floorToQuarterHour(date(2, 10, 15), calendar: calendar) == date(2, 10, 15))
        #expect(AvailabilityPolicy.floorToQuarterHour(date(2, 23, 59, 59), calendar: calendar) == date(2, 23, 45))
    }

    @Test("15分境界は分・秒・ナノ秒で判定する")
    func alignmentChecksSeconds() {
        #expect(AvailabilityPolicy.isQuarterHourAligned(date(2, 10, 45), calendar: calendar))
        #expect(!AvailabilityPolicy.isQuarterHourAligned(date(2, 10, 50), calendar: calendar))
        #expect(!AvailabilityPolicy.isQuarterHourAligned(date(2, 10, 45, 30), calendar: calendar))
    }

    @Test("秒を含む開始・終了を拒否する")
    func secondsAreRejected() {
        let candidate = slot(date(2, 10, 0, 30), date(2, 11, 0))

        #expect(throws: AvailabilityValidationError.notQuarterHour) {
            try AvailabilityPolicy.validate(candidate, now: now, existing: [], calendar: calendar)
        }
    }

    @Test("最短15分の枠を登録でき、開始と終了が同じ枠は拒否する")
    func minimumQuarterHourSlot() throws {
        try AvailabilityPolicy.validate(slot(date(2, 10, 0), date(2, 10, 15)), now: now, existing: [], calendar: calendar)

        #expect(throws: AvailabilityValidationError.invalidInterval) {
            try AvailabilityPolicy.validate(slot(date(2, 10, 0), date(2, 10, 0)), now: now, existing: [], calendar: calendar)
        }
        #expect(throws: AvailabilityValidationError.invalidInterval) {
            try AvailabilityPolicy.validate(slot(date(2, 10, 0), date(2, 9, 45)), now: now, existing: [], calendar: calendar)
        }
    }

    @Test("日付をまたぐ枠を許可する")
    func overnightSlotIsAllowed() throws {
        try AvailabilityPolicy.validate(slot(date(2, 23, 45), date(3, 0, 30)), now: now, existing: [], calendar: calendar)
    }

    @Test("現在ちょうどの開始は許可し、現在より前は拒否する")
    func pastBoundary() throws {
        let alignedNow = date(1, 12, 0)
        try AvailabilityPolicy.validate(
            slot(alignedNow, alignedNow.addingTimeInterval(900)),
            now: alignedNow,
            existing: [],
            calendar: calendar
        )

        #expect(throws: AvailabilityValidationError.past) {
            try AvailabilityPolicy.validate(
                slot(date(1, 11, 45), date(1, 12, 30)),
                now: alignedNow.addingTimeInterval(1),
                existing: [],
                calendar: calendar
            )
        }
    }

    @Test("14日ちょうどの終了は許可し、それを超える終了は拒否する")
    func windowBoundary() throws {
        let alignedNow = date(1, 12, 0)
        let windowEnd = alignedNow.addingTimeInterval(AvailabilityPolicy.window)
        try AvailabilityPolicy.validate(
            slot(windowEnd.addingTimeInterval(-3600), windowEnd),
            now: alignedNow,
            existing: [],
            calendar: calendar
        )

        #expect(throws: AvailabilityValidationError.outsideWindow) {
            try AvailabilityPolicy.validate(
                slot(windowEnd.addingTimeInterval(-3600), windowEnd.addingTimeInterval(900)),
                now: alignedNow,
                existing: [],
                calendar: calendar
            )
        }
    }

    @Test("登録できる最終時刻は14日後を15分境界へ切り下げた時刻")
    func latestEndIsFlooredWindowEnd() {
        let latest = AvailabilityPolicy.latestEnd(now: now, calendar: calendar)

        #expect(latest == date(15, 10, 0))
        #expect(latest <= now.addingTimeInterval(AvailabilityPolicy.window))
        #expect(AvailabilityPolicy.isQuarterHourAligned(latest, calendar: calendar))
    }

    @Test("既存枠の終了と同時刻に始まる枠は重複しない（半開区間）")
    func adjacentSlotIsAccepted() throws {
        let existing = slot(date(2, 10, 0), date(2, 12, 0))
        try AvailabilityPolicy.validate(slot(date(2, 12, 0), date(2, 13, 0)), now: now, existing: [existing], calendar: calendar)

        #expect(throws: AvailabilityValidationError.overlap(existing.id)) {
            try AvailabilityPolicy.validate(slot(date(2, 11, 45), date(2, 13, 0)), now: now, existing: [existing], calendar: calendar)
        }
    }

    @Test("位置指定なしの初期枠は次の15分境界から2時間")
    func draftWithoutAnchor() {
        let draft = AvailabilityPolicy.draftInterval(anchor: nil, now: now, calendar: calendar)

        #expect(draft?.start == date(1, 10, 15))
        #expect(draft?.end == date(1, 12, 15))
    }

    @Test("時間軸の位置は15分境界へ切り下げて開始にする")
    func draftFromTimelineAnchor() {
        let draft = AvailabilityPolicy.draftInterval(anchor: date(3, 22, 7, 40), now: now, calendar: calendar)

        #expect(draft?.start == date(3, 22, 0))
        #expect(draft?.end == date(4, 0, 0))
    }

    @Test("過去の位置を選んだ場合は次の15分境界へ引き上げる")
    func draftFromPastAnchorIsClamped() {
        let draft = AvailabilityPolicy.draftInterval(anchor: date(1, 8, 0), now: now, calendar: calendar)

        #expect(draft?.start == date(1, 10, 15))
    }

    @Test("14日範囲の末尾では終了を短縮し、15分も取れなければ開始しない")
    func draftNearWindowEnd() {
        let shortened = AvailabilityPolicy.draftInterval(anchor: date(15, 9, 0), now: now, calendar: calendar)
        #expect(shortened?.start == date(15, 9, 0))
        #expect(shortened?.end == date(15, 10, 0))

        let lastQuarter = AvailabilityPolicy.draftInterval(anchor: date(15, 9, 50), now: now, calendar: calendar)
        #expect(lastQuarter?.start == date(15, 9, 45))
        #expect(lastQuarter?.end == date(15, 10, 0))

        #expect(AvailabilityPolicy.draftInterval(anchor: date(15, 10, 0), now: now, calendar: calendar) == nil)
        #expect(AvailabilityPolicy.draftInterval(anchor: date(15, 12, 0), now: now, calendar: calendar) == nil)
    }

    @Test("表示タイムゾーンが変わっても同じ絶対時刻の枠として検証する")
    func timezoneDoesNotChangeAbsoluteInterval() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let candidate = slot(date(2, 10, 0), date(2, 12, 0))

        try AvailabilityPolicy.validate(candidate, now: now, existing: [], calendar: newYork)
        #expect(AvailabilityPolicy.floorToQuarterHour(date(2, 10, 7), calendar: newYork) == date(2, 10, 0))
    }
}

/// Deterministic clock shared by availability tests: 2026-09-01 10:07:30 in Asia/Tokyo.
enum AvailabilityTestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }()

    static let now = date(day: 1, hour: 10, minute: 7, second: 30)

    static func date(day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
    }
}
