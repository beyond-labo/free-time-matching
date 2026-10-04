import AppIntents
import Foundation

enum SystemActionIntentText {
    static func conditions(mode: HostingMode?, category: ActivityCategory?, area: HostingArea?) -> String {
        var values = [mode?.rawValue ?? "", category?.rawValue ?? "カテゴリ指定なし"]
        if mode == .offline { values.append(area?.rawValue ?? "あとで相談") }
        return values.filter { !$0.isEmpty }.joined(separator: "、")
    }
    static func interval(start: Date, end: Date, timeZoneIdentifier: String = TimeZone.current.identifier) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateFormat = "yyyy年M月d日 H:mm"
        return "\(formatter.string(from: start))から\(formatter.string(from: end))（\(timeZoneIdentifier)）"
    }
    static func confirmation(_ prepared: PreparedSystemAction, friends: [FriendEntity]) -> String {
        let input = prepared.input
        let dates = input.start.flatMap { start in input.end.map { interval(start: start, end: $0, timeZoneIdentifier: input.timeZoneIdentifier) } } ?? "選択した日時"
        let conditions = conditions(mode: input.mode, category: input.category, area: input.area)
        if input.kind == .cancelHosting { return "\(dates)、\(conditions)の募集を取り消しますか？" }
        return "\(dates)、\(conditions)で、\(friends.map(\.nickname).joined(separator: "、"))の全員に招待を送りますか？"
    }
}

enum SystemActionDateIssue: Equatable {
    case start(String), end(String)
    var message: String {
        switch self { case let .start(value), let .end(value): value }
    }
    static func validate(_ input: SystemActionInput, now: Date) -> Self? {
        guard input.kind != .cancelHosting, let start = input.start, let end = input.end,
              let zone = TimeZone(identifier: input.timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if start < now { return .start("開始日時は未来の日時を指定してください。") }
        if start >= now.addingTimeInterval(AvailabilityPolicy.window) { return .start("開始日時は14日以内を指定してください。") }
        if !AvailabilityPolicy.isQuarterHourAligned(start, calendar: calendar) { return .start("開始日時は15分単位を指定してください。") }
        if end <= start { return .end("終了日時は開始日時より後を指定してください。") }
        if end > now.addingTimeInterval(AvailabilityPolicy.window) { return .end("終了日時は14日以内を指定してください。") }
        if !AvailabilityPolicy.isQuarterHourAligned(end, calendar: calendar) { return .end("終了日時は15分単位を指定してください。") }
        return nil
    }
}

/// Apple runtime prompts stay in the intent layer; business decisions remain in the service.
protocol SystemActionIntent: ForegroundContinuableIntent {
    func dateParameterError(_ issue: SystemActionDateIssue) -> Error
}

extension SystemActionIntent {
    func dateParameterError(_ issue: SystemActionDateIssue) -> Error {
        NSError(domain: "SystemActionDate", code: 1, userInfo: [NSLocalizedDescriptionKey: issue.message])
    }
    func run(_ input: SystemActionInput, operationID: UUID, friends: [FriendEntity] = []) async throws -> String {
        let service = await AppRuntime.shared.systemActions
        if let record = try await service.record(operationID: operationID),
           record.state == .sending || record.state == .resultUnknown {
            // Resume a durable payload without re-resolving dates, IDs, or cancellation version.
            let outcome = try await service.retry(operationID: operationID)
            if outcome == .completed {
                let dates = record.input.start.flatMap { start in record.input.end.map {
                    SystemActionIntentText.interval(start: start, end: $0, timeZoneIdentifier: record.input.timeZoneIdentifier)
                } } ?? "選択した日時"
                return "\(dates)の操作を完了しました。"
            }
            try await handoff(operationID)
            return "操作の状態をアプリで確認してください。"
        }
        // Only fresh input is validated: persisted, possibly sent payloads must be replayed unchanged.
        if let issue = SystemActionDateIssue.validate(input, now: Date()) { throw dateParameterError(issue) }
        let preparation: ActionPreparation
        do {
            preparation = try await service.prepare(input, operationID: operationID)
        } catch SystemActionAccessError.accountStopped {
            return "このアカウントでは操作できません。"
        } catch SystemActionAccessError.accountChanged {
            return "アカウントが変わりました。対象を選び直してください。"
        } catch SystemActionAccessError.protectedDataUnavailable {
            return "端末のロックを解除して、もう一度実行してください。"
        } catch {
            let id = try await service.saveHandoff(input, operationID: operationID)
            try await handoff(id)
            return "入力を引き継ぎました。アプリで続けてください。"
        }
        guard case let .ready(prepared) = preparation else {
            let id = try await service.saveHandoff(input, operationID: operationID)
            if case let .invalidInput(reason) = preparation {
                try await handoff(id, dialog: IntentDialog(stringLiteral: reason + " アプリで確認・修正してください。"))
                return reason + " 入力を引き継ぎました。アプリで確認・修正してください。"
            }
            try await handoff(id)
            return "入力を引き継ぎました。アプリで続けてください。"
        }
        if prepared.requiresConfirmation {
            let dialog = IntentDialog(stringLiteral: SystemActionIntentText.confirmation(prepared, friends: friends))
            if #available(iOS 18.0, *) {
                try await requestConfirmation(actionName: .continue, dialog: dialog)
            } else {
                try await requestConfirmation(result: .result(dialog: dialog))
            }
        }
        // Persist the resolved input before execution can discover a conflict or access change.
        _ = try await service.saveHandoff(prepared)
        let outcome: ActionOutcome
        do {
            outcome = try await service.execute(prepared,
                confirmedFingerprint: prepared.requiresConfirmation ? prepared.confirmationFingerprint : nil)
        } catch {
            try await handoff(prepared.operationID)
            return "操作の状態をアプリで確認してください。"
        }
        switch outcome {
        case .completed:
            let dates = prepared.input.start.flatMap { start in prepared.input.end.map {
                SystemActionIntentText.interval(start: start, end: $0, timeZoneIdentifier: prepared.input.timeZoneIdentifier)
            } } ?? "選択した日時"
            switch input.kind {
            case .addAvailability: return "\(dates)の暇を登録しました。"
            case .subtractAvailability: return "\(dates)の暇を削除しました。"
            case .createHosting: return "\(dates)の募集を開始し、選んだ友達全員に招待を送りました。本人の暇も登録しました。参加OKの回答があると表示されます。"
            case .cancelHosting: return "\(dates)の募集を取り消しました。本人の暇は保持しています。"
            }
        case .blockedByHosting:
            try await handoff(prepared.operationID)
            return "募集中の時間が含まれています。アプリで募集を確認してください。"
        case .failed:
            try await handoff(prepared.operationID)
            return "操作を完了できませんでした。アプリで確認してください。"
        case .needsForeground, .conflict, .resultUnknown:
            // Never prepare or allocate a replacement operation after a possibly sent request.
            try await handoff(prepared.operationID)
            return "操作の状態をアプリで確認してください。"
        }
    }

    private func handoff(_ operationID: UUID, dialog: IntentDialog = "アプリで操作を続けます。") async throws {
        if #available(iOS 26.0, *) {
            try await continueInForeground(dialog)
        } else {
            try await requestToContinueInForeground(dialog)
        }
        await AppRuntime.shared.requestSystemActionHandoff(operationID: operationID)
    }
}
