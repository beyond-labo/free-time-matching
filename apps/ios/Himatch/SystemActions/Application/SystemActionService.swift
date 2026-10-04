import Foundation

actor SystemActionService {
    private let dependencies: SystemActionDependencies
    private var inFlight: Set<UUID> = []
    private var operationPayloads: [UUID: PreparedSystemAction] = [:]
    private var invalidatedOperationIDs: Set<UUID> = []
    private var preparedOwners: [UUID: String] = [:]
    private var mutationStarted: Set<UUID> = []
    private var replayOperationIDs: Set<UUID> = []
    private var cancelledBeforeDispatchIDs: Set<UUID> = []
    private var mutationTasks: [UUID: Task<ActionOutcome, Error>] = [:]

    init(dependencies: SystemActionDependencies) { self.dependencies = dependencies }

    private func owner(expected: String? = nil) async throws -> String {
        guard await dependencies.protectedDataAvailable() else { throw SystemActionAccessError.protectedDataUnavailable }
        let value = try await dependencies.authenticatedOwner()
        guard expected == nil || expected == value else { throw SystemActionAccessError.accountChanged }
        // A successfully restored same-owner session can resume its isolated unknown records.
        return value
    }

    func queryFriends(ownerUserID: String? = nil) async throws -> (ownerUserID: String, friends: [FriendProfile]) {
        let id = try await owner(expected: ownerUserID)
        let friends = try await dependencies.friendsForOwner(id)
        _ = try await owner(expected: id)
        return (id, friends)
    }

    func queryHostings(ownerUserID: String? = nil) async throws -> (ownerUserID: String, hostings: [Hosting]) {
        let id = try await owner(expected: ownerUserID)
        let result = try await dependencies.businessClientForOwner(id).loadHostings()
        _ = try await owner(expected: id)
        return (id, result.hostings.filter { $0.isHostedByMe && $0.status == .recruiting && $0.candidateRange.start > dependencies.now() })
    }

    func prepare(_ original: SystemActionInput, operationID: UUID? = nil) async throws -> ActionPreparation {
        if let operationID, invalidatedOperationIDs.contains(operationID) { return .invalidInput("この操作は失効しました。") }
        let id: String
        do { id = try await owner(expected: original.entityOwnerUserID) }
        catch SystemActionAccessError.needsAuthentication { return .needsAuthentication }
        catch SystemActionAccessError.profileRequired { return .needsAuthentication }
        catch { throw error }
        var input = original
        var version: Int?
        var mergeFingerprint = ""
        let client = dependencies.businessClientForOwner(id)
        if input.kind == .cancelHosting {
            guard let hostingID = input.hostingID else { return .needsDisambiguation }
            let result = try await client.loadHostings()
            guard let hosting = result.hostings.first(where: { $0.id == hostingID && $0.isHostedByMe && $0.status == .recruiting }),
                  hosting.candidateRange.start > dependencies.now() else { return .invalidInput("募集を取り消せません。") }
            input.start = hosting.candidateRange.start
            input.end = hosting.candidateRange.end
            input.mode = hosting.mode
            input.area = hosting.area
            input.category = hosting.category
            version = hosting.version
        } else {
            guard let start = input.start, let end = input.end,
                  let zone = TimeZone(identifier: input.timeZoneIdentifier) else { return .invalidInput("開始・終了日時を指定してください。") }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            do { try AvailabilityPolicy.validate(AvailabilitySlot(interval: .init(start: start, end: end)), now: dependencies.now(), existing: [], calendar: calendar) }
            catch { return .invalidInput("日時は未来の14日以内、15分単位で指定してください。") }
            if input.kind == .subtractAvailability {
                let hostings = try await client.loadHostings().hostings
                if hostings.contains(where: { $0.isHostedByMe && $0.status == .recruiting && $0.candidateRange.overlaps(.init(start: start, end: end)) }) {
                    return .invalidInput("募集中の時間は削除できません。先に募集を取り消してください。")
                }
            } else {
                let slots = try await client.loadAvailability()
                let metadata = mergedMetadata(slots: slots, start: start, end: end)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                mergeFingerprint = (try encoder.encode(metadata)).base64EncodedString()
                if let selected = input.availabilityMetadata {
                    input.availabilityMetadata = selected
                } else if metadata.count > 1 {
                    return .needsMetadataSelection(metadata)
                } else {
                    input.availabilityMetadata = metadata.first ?? SystemActionMetadata()
                }
            }
            if input.kind == .createHosting {
                guard input.mode != nil, !input.friendIDs.isEmpty,
                      Set(input.friendIDs).count == input.friendIDs.count else { return .needsDisambiguation }
                let friends = try await dependencies.friendsForOwner(id)
                guard input.friendIDs.allSatisfy({ target in friends.contains { $0.id == target } }) else { return .needsDisambiguation }
                if input.mode == .offline && input.area == nil { input.area = .discussLater }
                if input.mode == .online { input.area = nil }
            }
        }
        _ = try await owner(expected: id)
        let operation = PreparedSystemAction(operationID: operationID ?? dependencies.uuid(), ownerUserID: id,
                                            input: input, expectedVersion: version, confirmationFingerprint: fingerprint(input, version: version) + ":" + mergeFingerprint)
        preparedOwners[operation.operationID] = id
        return .ready(operation)
    }

    /// Finds the full touching OR component, including slots reached only transitively.
    private func mergedMetadata(slots: [AvailabilitySlot], start: Date, end: Date) -> [SystemActionMetadata] {
        var lower = start, upper = end
        var selected: Set<UUID> = []
        var changed = true
        while changed {
            changed = false
            for slot in slots where !selected.contains(slot.id) && slot.interval.start <= upper && slot.interval.end >= lower {
                selected.insert(slot.id); lower = min(lower, slot.interval.start); upper = max(upper, slot.interval.end); changed = true
            }
        }
        var result: [SystemActionMetadata] = []
        for slot in slots where selected.contains(slot.id) {
            let value = SystemActionMetadata(category: slot.category, visibility: slot.visibility)
            if !result.contains(value) { result.append(value) }
        }
        // New time contributes private/unselected metadata; sharing it always requires a choice.
        var coveredUntil = start
        for slot in slots.sorted(by: { $0.interval.start < $1.interval.start }) where selected.contains(slot.id) {
            if slot.interval.start > coveredUntil { break }
            coveredUntil = max(coveredUntil, slot.interval.end)
        }
        if coveredUntil < end && !result.contains(SystemActionMetadata()) { result.append(SystemActionMetadata()) }
        return result
    }

    private func fingerprint(_ input: SystemActionInput, version: Int?) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ((try? encoder.encode(input).base64EncodedString()) ?? "") + ":" + String(version ?? 0)
    }

    func execute(_ operation: PreparedSystemAction, confirmedFingerprint: String? = nil) async throws -> ActionOutcome {
        guard !inFlight.contains(operation.operationID) else { return .needsForeground }
        guard !invalidatedOperationIDs.contains(operation.operationID) else { return .needsForeground }
                _ = try await owner(expected: operation.ownerUserID)
        if operation.requiresConfirmation && confirmedFingerprint != operation.confirmationFingerprint { return .needsForeground }
        let existing = try await dependencies.journal.records().first { $0.operationID == operation.operationID }
        if let existing {
            if let prepared = existing.prepared { guard prepared == operation else { return .conflict } }
            else if existing.state == .sending || existing.state == .resultUnknown { return .resultUnknown }
            if existing.state == .sending || existing.state == .resultUnknown { return try await retry(operationID: operation.operationID) }
        }
        guard case let .ready(latest) = try await prepare(operation.input, operationID: operation.operationID),
              latest == operation else { return .conflict }
        return try await send(operation, createdAt: existing?.createdAt ?? dependencies.now(), replay: false)
    }

    private func send(_ operation: PreparedSystemAction, createdAt: Date, replay: Bool) async throws -> ActionOutcome {
        guard !inFlight.contains(operation.operationID) else { return .needsForeground }
        if let previous = operationPayloads[operation.operationID], previous != operation { return .conflict }
        operationPayloads[operation.operationID] = operation
        preparedOwners[operation.operationID] = operation.ownerUserID
        if replay { replayOperationIDs.insert(operation.operationID) }
        inFlight.insert(operation.operationID)
        defer {
            inFlight.remove(operation.operationID)
            cancelledBeforeDispatchIDs.remove(operation.operationID)
        }
        _ = try await owner(expected: operation.ownerUserID)
        var record = SystemActionRecord(operationID: operation.operationID, ownerUserID: operation.ownerUserID,
                                       input: operation.input, expectedVersion: operation.expectedVersion,
                                       confirmationFingerprint: operation.confirmationFingerprint, state: .sending, createdAt: createdAt)
        // The durable payload is committed before any network mutation.
        try await dependencies.journal.save(record)
        if invalidatedOperationIDs.contains(operation.operationID) || cancelledBeforeDispatchIDs.contains(operation.operationID) {
            if replay {
                record.state = .resultUnknown
                try await dependencies.journal.save(record)
            } else { try await dependencies.journal.remove(operation.operationID) }
            return .needsForeground
        }
        let client = dependencies.businessClientForOwner(operation.ownerUserID)
        mutationStarted.insert(operation.operationID)
        do {
            let mutation = Task<ActionOutcome, Error> {
            let input = operation.input
            switch input.kind {
            case .addAvailability:
                guard let start = input.start, let end = input.end, let metadata = input.availabilityMetadata else { return .failed("入力が不足しています。") }
                _ = try await client.addAvailability(.init(id: operation.operationID, interval: .init(id: operation.operationID, start: start, end: end), category: metadata.category, visibility: metadata.visibility))
            case .subtractAvailability:
                guard let start = input.start, let end = input.end else { return .failed("入力が不足しています。") }
                _ = try await client.subtractAvailability(.init(id: operation.operationID, start: start, end: end), operation.operationID)
            case .createHosting:
                guard let start = input.start, let end = input.end, let mode = input.mode, let metadata = input.availabilityMetadata else { return .failed("入力が不足しています。") }
                // Stable friend IDs and array order are the mutation payload; profile labels are not used.
                let friends = input.friendIDs.map { FriendProfile(id: $0, displayName: "", icon: "") }
                _ = try await client.createHosting(.init(mode: mode, area: input.area, category: input.category, start: start,
                                                        duration: end.timeIntervalSince(start), friends: friends,
                                                        availabilityMetadata: .init(category: metadata.category, visibility: metadata.visibility),
                                                        operationID: operation.operationID))
            case .cancelHosting:
                guard let hostingID = input.hostingID, let version = operation.expectedVersion else { return .failed("入力が不足しています。") }
                _ = try await client.cancelHosting(hostingID, operation.operationID, version)
            }
            return .completed
            }
            mutationTasks[operation.operationID] = mutation
            defer { mutationTasks.removeValue(forKey: operation.operationID) }
            let result = try await mutation.value
            guard result == .completed else { return result }
            record.state = .completed
            try await dependencies.journal.save(record)
            try await dependencies.journal.remove(operation.operationID)
            return .completed
        } catch let error as BackendClientError {
            switch error {
            case .response(409, _):
                record.state = replay ? .resultUnknown : .conflict
                try await dependencies.journal.save(record)
                return replay ? .resultUnknown : .conflict
            case .response(401, _):
                record.state = replay ? .resultUnknown : .awaitingForeground
                try await dependencies.journal.save(record)
                return .needsForeground
            case .response(400, _), .response(403, _), .response(404, _), .response(422, _):
                record.state = replay ? .resultUnknown : .awaitingForeground
                try await dependencies.journal.save(record)
                return replay ? .resultUnknown : .failed("操作を完了できませんでした。アプリで確認してください。")
            default: break
            }
        } catch is SystemActionAccessError {
            // Owner-bound client access failures occur before HTTP dispatch.
            record.state = replay ? .resultUnknown : .awaitingForeground
            try await dependencies.journal.save(record)
            return .needsForeground
        } catch { }
        record.state = .resultUnknown
        // A lock may make this write fail; durable sending remains an unknown outcome on recovery.
        try? await dependencies.journal.save(record)
        return .resultUnknown
    }

    func retry(operationID: UUID) async throws -> ActionOutcome {
        guard let record = try await dependencies.journal.records().first(where: { $0.operationID == operationID }),
              let prepared = record.prepared,
              record.state == .sending || record.state == .resultUnknown else { return .needsForeground }
        _ = try await owner(expected: prepared.ownerUserID)
        return try await send(prepared, createdAt: record.createdAt, replay: true)
    }

    @discardableResult
    func saveHandoff(_ input: SystemActionInput, operationID: UUID? = nil) async throws -> UUID {
        let id = operationID ?? dependencies.uuid()
        let existing = try await dependencies.journal.records().first { $0.operationID == id }
        if let existing {
            guard existing.input == input else { throw SystemActionAccessError.accountChanged }
            return id
        }
        guard await dependencies.protectedDataAvailable() else { throw SystemActionAccessError.protectedDataUnavailable }
        let restored = try await dependencies.restoredOwnerID()
        if let restored, let entityOwner = input.entityOwnerUserID, restored != entityOwner {
            throw SystemActionAccessError.accountChanged
        }
        let user = restored ?? input.entityOwnerUserID
        try await dependencies.journal.save(.init(operationID: id, ownerUserID: user, input: input,
                                                  state: .awaitingForeground, createdAt: dependencies.now()))
        return id
    }

    @discardableResult
    func saveHandoff(_ operation: PreparedSystemAction) async throws -> UUID {
        _ = try await owner(expected: operation.ownerUserID)
        let existing = try await dependencies.journal.records().first { $0.operationID == operation.operationID }
        if let existing {
            if existing.state == .sending || existing.state == .resultUnknown || existing.prepared != nil {
                guard existing.prepared == operation else { throw SystemActionAccessError.accountChanged }
                return operation.operationID
            }
            guard existing.ownerUserID == nil || existing.ownerUserID == operation.ownerUserID else { throw SystemActionAccessError.accountChanged }
        }
        try await dependencies.journal.save(.init(operationID: operation.operationID, ownerUserID: operation.ownerUserID,
                                                  input: operation.input, expectedVersion: operation.expectedVersion,
                                                  confirmationFingerprint: operation.confirmationFingerprint,
                                                  state: .awaitingForeground, createdAt: existing?.createdAt ?? dependencies.now()))
        return operation.operationID
    }

    @discardableResult
    func updateInput(operationID: UUID, input: SystemActionInput) async throws -> UUID {
        guard var record = try await dependencies.journal.records().first(where: { $0.operationID == operationID }),
              record.state != .sending && record.state != .resultUnknown else { throw SystemActionAccessError.accountChanged }
        record.ownerUserID = try await owner(expected: record.ownerUserID ?? input.entityOwnerUserID)
        if let entityOwner = input.entityOwnerUserID, entityOwner != record.ownerUserID { throw SystemActionAccessError.accountChanged }
        let replaceID = record.state == .conflict || record.prepared != nil || operationPayloads[operationID] != nil
        if replaceID {
            record.operationID = dependencies.uuid()
            record.createdAt = dependencies.now()
        }
        record.input = input; record.expectedVersion = nil; record.confirmationFingerprint = nil; record.state = .draft
        // Preserve the original input if the replacement cannot be durably saved.
        try await dependencies.journal.save(record)
        if replaceID {
            invalidatedOperationIDs.insert(operationID)
            operationPayloads.removeValue(forKey: operationID)
            preparedOwners.removeValue(forKey: operationID)
            mutationStarted.remove(operationID)
            replayOperationIDs.remove(operationID)
            try await dependencies.journal.remove(operationID)
        }
        return record.operationID
    }

    func record(operationID: UUID) async throws -> SystemActionRecord? {
        guard await dependencies.protectedDataAvailable() else { return nil }
        guard let record = try await dependencies.journal.records().first(where: { $0.operationID == operationID }) else { return nil }
        if let id = record.ownerUserID { _ = try await owner(expected: id) }
        return record
    }

    func pendingHandoff() async throws -> SystemActionHandoff? {
        guard await dependencies.protectedDataAvailable() else { return nil }
        let current = try? await owner()
        return try await dependencies.journal.records().first {
            $0.state != .completed && !inFlight.contains($0.operationID)
                && ($0.ownerUserID == nil || $0.ownerUserID == current)
                && ($0.input.entityOwnerUserID == nil || $0.input.entityOwnerUserID == current)
        }
    }

    func discard(operationID: UUID) async throws {
        guard !inFlight.contains(operationID) else { return }
        if let record = try await dependencies.journal.records().first(where: { $0.operationID == operationID }), let id = record.ownerUserID {
            _ = try await owner(expected: id)
        }
        try await dependencies.journal.remove(operationID)
    }

    func invalidate(ownerUserID: String) async throws {
        for id in inFlight where preparedOwners[id] == ownerUserID && !mutationStarted.contains(id) { cancelledBeforeDispatchIDs.insert(id) }
        for (id, task) in mutationTasks where preparedOwners[id] == ownerUserID { task.cancel() }
        for (id, owner) in preparedOwners where owner == ownerUserID && !mutationStarted.contains(id) && !replayOperationIDs.contains(id) { invalidatedOperationIDs.insert(id) }
                for record in try await dependencies.journal.records() where record.ownerUserID == ownerUserID
            || record.input.entityOwnerUserID == ownerUserID || record.ownerUserID == nil {
            // A sending snapshot can precede dispatch. Never resurrect an invalidated unsent action.
            if invalidatedOperationIDs.contains(record.operationID) && !mutationStarted.contains(record.operationID) && !replayOperationIDs.contains(record.operationID) {
                try await dependencies.journal.remove(record.operationID)
            } else if record.ownerUserID != nil && (record.state == .sending || record.state == .resultUnknown) {
                var unknown = record; unknown.state = .resultUnknown
                try await dependencies.journal.save(unknown)
            } else {
                invalidatedOperationIDs.insert(record.operationID)
                try await dependencies.journal.remove(record.operationID)
            }
        }
    }
}
