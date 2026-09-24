import Foundation

/// Display strings for availability. Stored values stay absolute `Date`s; these helpers only
/// render them in the given calendar's time zone.
enum AvailabilityFormatting {
    static let locale = Locale(identifier: "ja_JP")

    static func time(_ date: Date, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .hour(.defaultDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    /// e.g. "9月24日(木)"
    static func day(_ date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日(\(weekday(date, calendar: calendar)))"
    }

    /// e.g. "9/24"
    static func shortDay(_ date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }

    /// e.g. "木"
    static func weekday(_ date: Date, calendar: Calendar) -> String {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        return symbols[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    /// "3時間30分", "45分", "2時間"
    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)分"
        case (_, 0): return "\(hours)時間"
        default: return "\(hours)時間\(minutes)分"
        }
    }

    static func isOvernight(start: Date, end: Date, calendar: Calendar) -> Bool {
        end > start && !calendar.isDate(start, inSameDayAs: end.addingTimeInterval(-1))
    }

    /// "9月24日(木) 22:00〜翌1:30" style range used in cards and accessibility labels.
    static func range(_ interval: TimeIntervalRange, calendar: Calendar) -> String {
        let start = "\(day(interval.start, calendar: calendar)) \(time(interval.start, calendar: calendar))"
        let endTime = time(interval.end, calendar: calendar)
        if calendar.isDate(interval.start, inSameDayAs: interval.end) {
            return "\(start)〜\(endTime)"
        }
        let daysBetween = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: interval.start),
            to: calendar.startOfDay(for: interval.end)
        ).day ?? 0
        if daysBetween == 1 {
            return "\(start)〜翌\(endTime)"
        }
        return "\(start)〜\(day(interval.end, calendar: calendar)) \(endTime)"
    }

    /// "日本標準時（GMT+9）"
    static func timeZone(_ calendar: Calendar, at date: Date) -> String {
        let zone = calendar.timeZone
        let name = zone.localizedName(for: zone.isDaylightSavingTime(for: date) ? .daylightSaving : .standard, locale: locale)
            ?? zone.identifier
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        let offset = minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
        return "\(name)（\(offset)）"
    }
}

extension AvailabilityValidationError {
    /// User-facing reason shown next to the time inputs.
    var message: String {
        switch self {
        case .invalidInterval: "終了は開始より後にしてください。"
        case .past: "開始時刻が過ぎています。次の15分からに合わせてください。"
        case .outsideWindow: "登録できるのは今後14日以内です。終了を早めてください。"
        case .notQuarterHour: "開始と終了は15分単位で指定してください。"
        case .overlap: "登録済みの暇と重なっています。重なっている暇を確認してください。"
        }
    }
}

extension AvailabilityValidationError {
    /// Short reason shown on the selection block itself.
    var shortLabel: String {
        switch self {
        case .invalidInterval: "時間が不正"
        case .past: "過ぎた時間"
        case .outsideWindow: "14日より先"
        case .notQuarterHour: "15分単位ではない"
        case .overlap: "登録済みの暇と重複"
        }
    }
}

extension AvailabilityVisibility {
    var systemImage: String {
        switch self {
        case .privateUntilAccepted: "lock.fill"
        case .shareOnHosting: "person.crop.circle.badge.checkmark"
        }
    }

    var explanation: String {
        switch self {
        case .privateUntilAccepted:
            "システムが重なりを確認して招待を届けます。参加OKするまでは主催者に暇時間を表示しません。"
        case .shareOnHosting:
            "友達が募集を始めたとき、募集と重なる暇時間を主催者に表示します。自動で参加OKにはなりません。"
        }
    }
}

extension ActivityCategory {
    var systemImage: String {
        switch self {
        case .game: "gamecontroller.fill"
        case .meal: "fork.knife"
        case .call: "phone.fill"
        case .work: "laptopcomputer"
        }
    }
}
