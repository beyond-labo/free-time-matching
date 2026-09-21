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
