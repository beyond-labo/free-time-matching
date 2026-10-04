import Foundation
import Testing
@testable import Himatch

private actor ActionTestState {
    var records: [SystemActionRecord] = []
    var sent: [AvailabilitySlot] = []
    var fail = false
    func all() -> [SystemActionRecord] { records.sorted { $0.createdAt < $1.createdAt } }
    func save(_ record: SystemActionRecord) { records.removeAll { $0.id == record.id }; records.append(record) }
    func remove(_ id: UUID) { records.removeAll { $0.id == id } }
    func send(_ slot: AvailabilitySlot) throws -> AppSnapshot {
        sent.append(slot)
        if fail { throw URLError(.networkConnectionLost) }
        return .empty()
    }
    func setFailure(_ value: Bool) { fail = value }
    func sentIDs() -> [UUID] { sent.map(\.id) }
}

struct SystemActionServiceTests: Sendable {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func make(state: ActionTestState, slots: [AvailabilitySlot] = [], authenticated: Bool = true) -> SystemActionService {
        var client = HimatchClient.productionPlaceholder
        client.loadAvailability = { slots }
        client.addAvailability = { try await state.send($0) }
        let boundClient = client
        return SystemActionService(dependencies: .init(
            authenticatedOwner: { if !authenticated { throw SystemActionAccessError.needsAuthentication }; return "owner" },
            businessClientForOwner: { _ in boundClient }, friendsForOwner: { _ in [] }, protectedDataAvailable: { true },
            journal: .init(records: { await state.all() }, save: { await state.save($0) }, remove: { await state.remove($0) }), now: { now }))
    }
    private func input(start: Date? = nil, end: Date? = nil) -> SystemActionInput {
        .init(kind: .addAvailability, start: start ?? now.addingTimeInterval(900), end: end ?? now.addingTimeInterval(1800), timeZoneIdentifier: "UTC")
    }

    @Test func rejectsInvalidDatesWithoutMutation() async throws {
        let state = ActionTestState(); let service = make(state: state)
        let result = try await service.prepare(input(start: now.addingTimeInterval(1)))
        guard case .invalidInput = result else { Issue.record("Expected invalid date"); return }
        #expect(await state.sentIDs().isEmpty)
        #expect(await state.all().isEmpty)
    }

    @Test func authenticationRequiresForeground() async throws {
        let state = ActionTestState(); let service = make(state: state, authenticated: false)
        #expect(try await service.prepare(input()) == .needsAuthentication)
        let id = try await service.saveHandoff(input())
        #expect(try await service.pendingHandoff()?.operationID == id)
    }

    @Test func touchingChainRequiresMetadataChoice() async throws {
        let start = now.addingTimeInterval(900)
        let slots = [
            AvailabilitySlot(interval: .init(start: start.addingTimeInterval(900), end: start.addingTimeInterval(1800)), category: .game),
            AvailabilitySlot(interval: .init(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(2700)), category: .meal)
        ]
        let service = make(state: ActionTestState(), slots: slots)
        guard case let .needsMetadataSelection(choices) = try await service.prepare(input()) else { Issue.record("Expected metadata choice"); return }
        #expect(choices.count == 3)
    }

    @Test func unknownRetryPreservesOperationAndPayload() async throws {
        let state = ActionTestState(); let service = make(state: state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { Issue.record("Expected ready"); return }
        await state.setFailure(true)
        #expect(try await service.execute(prepared) == .resultUnknown)
        let recorded = try await service.record(operationID: prepared.operationID)
        #expect(recorded?.prepared == prepared)
        await state.setFailure(false)
        #expect(try await service.retry(operationID: prepared.operationID) == .completed)
        #expect(await state.sentIDs() == [prepared.operationID, prepared.operationID])
        #expect(await state.all().isEmpty)
    }

    @Test func unknownInputCannotBeEdited() async throws {
        let state = ActionTestState(); let service = make(state: state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.setFailure(true)
        _ = try await service.execute(prepared)
        await #expect(throws: SystemActionAccessError.self) { try await service.updateInput(operationID: prepared.operationID, input: input(end: now.addingTimeInterval(2700))) }
    }
}

private actor SafetyActionState {
    var owner = "owner"
    var slots: [AvailabilitySlot] = []
    var friends: [FriendProfile] = []
    var hostings: [Hosting] = []
    var records: [SystemActionRecord] = []
    var sends = 0
    var saveFails = false
    var failure: BackendClientError?
    var transportFails = false
    var accessFailure: SystemActionAccessError?
    var profileFails = false
    var suspendSend = false
    var continuation: CheckedContinuation<Void, Never>?
    var draft: HostingDraft?
    var suspendSendingSave = false
    var sendingSaveWaiting = false
    var sendingSaveContinuation: CheckedContinuation<Void, Never>?
    var suspendSendingSnapshot = false
    var sendingSnapshotWaiting = false
    var snapshotContinuation: CheckedContinuation<Void, Never>?
    func setAccessFailure(_ value: SystemActionAccessError?) { accessFailure = value }
    func failProfile() { profileFails = true }
    func authenticated() throws -> String { if profileFails { throw URLError(.notConnectedToInternet) }; return owner }
    func setOwner(_ value: String) { owner = value }
    func setSlots(_ value: [AvailabilitySlot]) { slots = value }
    func setFriends(_ value: [FriendProfile]) { friends = value }
    func setHostings(_ value: [Hosting]) { hostings = value }
    func failSave() { saveFails = true }
    func setTransportFailure(_ value: Bool) { transportFails = value }
    func setFailure(_ value: BackendClientError?) { failure = value }
    func suspend() { suspendSend = true }
    func resume() { continuation?.resume(); continuation = nil }
    func save(_ record: SystemActionRecord) async throws {
        if saveFails { throw URLError(.cannotWriteToFile) }
        records.removeAll { $0.id == record.id }; records.append(record)
        if suspendSendingSave && record.state == .sending {
            sendingSaveWaiting = true
            await withCheckedContinuation { sendingSaveContinuation = $0 }
        }
    }
    func configureInvalidationRace() { suspendSendingSave = true; suspendSendingSnapshot = true }
    func releaseSendingSave() { suspendSendingSave = false; sendingSaveContinuation?.resume(); sendingSaveContinuation = nil }
    func releaseSnapshot() { suspendSendingSnapshot = false; snapshotContinuation?.resume(); snapshotContinuation = nil }
    func allRecords() async -> [SystemActionRecord] {
        let snapshot = records
        if suspendSendingSnapshot && snapshot.contains(where: { $0.state == .sending }) {
            sendingSnapshotWaiting = true
            await withCheckedContinuation { snapshotContinuation = $0 }
        }
        return snapshot
    }
    func remove(_ id: UUID) { records.removeAll { $0.id == id } }
    func send(_ input: HostingDraft? = nil) async throws -> AppSnapshot {
        sends += 1; draft = input
        if suspendSend { await withCheckedContinuation { continuation = $0 } }
        if let accessFailure { throw accessFailure }
        if let failure { throw failure }
        if transportFails { throw URLError(.networkConnectionLost) }
        return .empty()
    }
}

struct SystemActionSafetyTests: Sendable {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func input(_ kind: SystemActionKind = .addAvailability) -> SystemActionInput {
        .init(kind: kind, start: now.addingTimeInterval(900), end: now.addingTimeInterval(1800), timeZoneIdentifier: "Asia/Tokyo")
    }
    private func service(_ state: SafetyActionState, locked: Bool = false) -> SystemActionService {
        var client = HimatchClient.productionPlaceholder
        client.loadAvailability = { await state.slots }
        client.loadHostings = { (await state.hostings, []) }
        client.addAvailability = { _ in try await state.send() }
        client.subtractAvailability = { _, _ in try await state.send() }
        client.createHosting = { try await state.send($0) }
        client.cancelHosting = { _, _, _ in try await state.send() }
        let bound = client
        return .init(dependencies: .init(authenticatedOwner: { try await state.authenticated() }, businessClientForOwner: { _ in bound },
            friendsForOwner: { _ in await state.friends }, protectedDataAvailable: { !locked },
            journal: .init(records: { await state.allRecords() }, save: { try await state.save($0) }, remove: { await state.remove($0) }), restoredOwnerID: { await state.owner }, now: { now }))
    }
    func hosting() -> Hosting {
        .init(id: UUID(), mode: .online, candidateRange: .init(start: now.addingTimeInterval(900), end: now.addingTimeInterval(1800)), requiredDuration: 900, friends: [], participants: [], status: .recruiting)
    }

    @Test func recruitingIntervalCannotBeSubtracted() async throws {
        let state = SafetyActionState(); await state.setHostings([hosting()])
        guard case .invalidInput = try await service(state).prepare(input(.subtractAvailability)) else { Issue.record("Expected blocked interval"); return }
        #expect(await state.sends == 0)
    }

    @Test func sameNameFriendsKeepIDsAndRevokedFriendCannotSend() async throws {
        let state = SafetyActionState()
        let friends = [FriendProfile(id: UUID(), displayName: "同名", icon: "sun"), FriendProfile(id: UUID(), displayName: "同名", icon: "moon")]
        await state.setFriends(friends)
        let service = service(state)
        let candidates = try await service.queryFriends()
        #expect(Set(candidates.friends.map(\.id)).count == 2)
        var request = input(.createHosting); request.mode = .online; request.friendIDs = [friends[0].id]
        guard case let .ready(prepared) = try await service.prepare(request) else { Issue.record("Expected ready"); return }
        await state.setFriends([])
        #expect(try await service.execute(prepared, confirmedFingerprint: prepared.confirmationFingerprint) == .conflict)
        #expect(await state.sends == 0)
    }

    @Test func lockStopsSensitiveQueries() async throws {
        let service = service(SafetyActionState(), locked: true)
        await #expect(throws: SystemActionAccessError.protectedDataUnavailable) { try await service.queryFriends() }
        await #expect(throws: SystemActionAccessError.protectedDataUnavailable) { try await service.queryHostings() }
    }

    @Test func latestVersionAndMetadataInvalidateConfirmation() async throws {
        let state = SafetyActionState(); var target = hosting(); await state.setHostings([target])
        let service = service(state)
        var request = SystemActionInput(kind: .cancelHosting); request.hostingID = target.id
        guard case let .ready(prepared) = try await service.prepare(request) else { return }
        target.version += 1; await state.setHostings([target])
        #expect(try await service.execute(prepared, confirmedFingerprint: prepared.confirmationFingerprint) == .conflict)
        #expect(await state.sends == 0)
        guard case let .ready(add) = try await service.prepare(input()) else { return }
        await state.setSlots([.init(interval: .init(start: request.start ?? now.addingTimeInterval(900), end: now.addingTimeInterval(1800)), category: .meal)])
        #expect(try await service.execute(add) == .conflict)
        #expect(await state.sends == 0)
    }

    @Test func failedDurableSavePreventsHTTP() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.failSave()
        await #expect(throws: URLError.self) { try await service.execute(prepared) }
        #expect(await state.sends == 0)
    }

    @Test func sendingRejectsDuplicateExecution() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.suspend()
        let first = Task { try await service.execute(prepared) }
        while await state.sends == 0 { await Task.yield() }
        #expect(try await service.execute(prepared) == .needsForeground)
        #expect(await state.sends == 1)
        await state.resume()
        #expect(try await first.value == .completed)
    }

    @Test func replay409RemainsUnknownAndDifferentOwnerCannotRetry() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.setTransportFailure(true)
        #expect(try await service.execute(prepared) == .resultUnknown)
        await state.setTransportFailure(false); await state.setFailure(.response(409, nil))
        #expect(try await service.retry(operationID: prepared.operationID) == .resultUnknown)
        #expect(try await service.record(operationID: prepared.operationID)?.state == .resultUnknown)
        await state.setOwner("another")
        await #expect(throws: SystemActionAccessError.accountChanged) { try await service.retry(operationID: prepared.operationID) }
        #expect(await state.sends == 2)
    }

    @Test func preparedOperationIsInvalidatedButUnknownCanResumeForOriginalOwner() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        try await service.invalidate(ownerUserID: "owner")
        #expect(try await service.execute(prepared) == .needsForeground)
        #expect(await state.sends == 0)
        guard case let .ready(newAction) = try await service.prepare(input()) else { return }
        await state.setTransportFailure(true)
        #expect(try await service.execute(newAction) == .resultUnknown)
        try await service.invalidate(ownerUserID: "owner")
        await state.setTransportFailure(false)
        #expect(try await service.retry(operationID: newAction.operationID) == .completed)
    }

    @Test func midnightAndTimezoneKeepAbsoluteDatesAndHostingCategorySeparate() async throws {
        let state = SafetyActionState(); let friend = FriendProfile(id: UUID(), displayName: "友達", icon: "sun")
        await state.setFriends([friend]); let service = service(state)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = calendar.startOfDay(for: now).addingTimeInterval(23 * 3600 + 45 * 60)
        var request = SystemActionInput(kind: .createHosting, start: start, end: start.addingTimeInterval(1800), timeZoneIdentifier: "Asia/Tokyo", friendIDs: [friend.id], mode: .online, category: .game)
        if start < now { request.start = start.addingTimeInterval(86400); request.end = start.addingTimeInterval(88200) }
        guard case let .ready(prepared) = try await service.prepare(request) else { Issue.record("Expected midnight interval ready"); return }
        #expect(prepared.input.start == request.start)
        #expect(prepared.input.end == request.end)
        #expect(prepared.input.timeZoneIdentifier == "Asia/Tokyo")
        #expect(try await service.execute(prepared, confirmedFingerprint: prepared.confirmationFingerprint) == .completed)
        let draft = await state.draft
        #expect(draft?.category == .game)
        #expect(draft?.availabilityMetadata != nil)
        #expect(draft?.availabilityMetadata?.category == nil)
        #expect(draft?.availabilityMetadata?.visibility == .privateUntilAccepted)
    }
    @Test func touchingSharedSlotRequiresExplicitChoiceForNewTime() async throws {
        let state = SafetyActionState()
        await state.setSlots([.init(interval: .init(start: now.addingTimeInterval(1800), end: now.addingTimeInterval(2700)), category: .game, visibility: .shareOnHosting)])
        let service = service(state)
        guard case let .needsMetadataSelection(choices) = try await service.prepare(input()) else { Issue.record("New private time must not inherit sharing"); return }
        #expect(choices.contains(SystemActionMetadata()))
        #expect(choices.contains(.init(category: .game, visibility: .shareOnHosting)))
        #expect(await state.sends == 0)
    }

    @Test func offlineProfileHandoffRemainsBoundToSessionOwner() async throws {
        let state = SafetyActionState(); let service = service(state)
        await state.failProfile()
        let id = try await service.saveHandoff(input())
        #expect(await state.records.first?.ownerUserID == "owner")
        await state.setOwner("another")
        #expect(try await service.pendingHandoff() == nil)
        try await service.invalidate(ownerUserID: "owner")
        #expect(await state.records.isEmpty)
        await #expect(throws: SystemActionAccessError.accountChanged) {
            var request = input(); request.entityOwnerUserID = "owner"
            try await service.saveHandoff(request)
        }
        _ = id
    }

    @Test func pendingQueueDoesNotExposeSendingOperation() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.suspend()
        let sending = Task { try await service.execute(prepared) }
        while await state.sends == 0 { await Task.yield() }
        #expect(try await service.pendingHandoff() == nil)
        await state.resume()
        _ = try await sending.value
    }

    @Test func preDispatchAccessStopIsKnownUnsent() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.setAccessFailure(.accountStopped)
        #expect(try await service.execute(prepared) == .needsForeground)
        #expect(try await service.record(operationID: prepared.operationID)?.state == .awaitingForeground)
    }

    @Test func knownRejectionEditedInputReceivesFreshOperationID() async throws {
        for failure in [BackendClientError.response(401, nil), .response(403, nil), .response(422, nil)] {
            let state = SafetyActionState(); let service = service(state)
            guard case let .ready(prepared) = try await service.prepare(input()) else { return }
            await state.setFailure(failure)
            _ = try await service.execute(prepared)
            var edited = input(); edited.end = now.addingTimeInterval(2700)
            let replacementID = try await service.updateInput(operationID: prepared.operationID, input: edited)
            #expect(replacementID != prepared.operationID)
            #expect(try await service.record(operationID: prepared.operationID) == nil)
            await state.setFailure(nil)
            guard case let .ready(replacement) = try await service.prepare(edited, operationID: replacementID) else { return }
            #expect(try await service.execute(replacement) == .completed)
            #expect(await state.sends == 2)
            #expect(try await service.execute(prepared) == .needsForeground)
        }
    }

    @Test func knownPreDispatchRejectionEditedInputReceivesFreshOperationID() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.setAccessFailure(.needsAuthentication)
        #expect(try await service.execute(prepared) == .needsForeground)
        var edited = input(); edited.end = now.addingTimeInterval(2700)
        let replacementID = try await service.updateInput(operationID: prepared.operationID, input: edited)
        #expect(replacementID != prepared.operationID)
        await state.setAccessFailure(nil)
        guard case let .ready(replacement) = try await service.prepare(edited, operationID: replacementID) else { return }
        #expect(try await service.execute(replacement) == .completed)
    }

    @Test func invalidationSendingSnapshotCannotResurrectUnsentOperation() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.configureInvalidationRace()
        let sending = Task { try await service.execute(prepared) }
        while !(await state.sendingSaveWaiting) { await Task.yield() }
        let invalidating = Task { try await service.invalidate(ownerUserID: "owner") }
        while !(await state.sendingSnapshotWaiting) { await Task.yield() }
        await state.releaseSendingSave()
        #expect(try await sending.value == .needsForeground)
        #expect(await state.records.isEmpty)
        await state.releaseSnapshot()
        try await invalidating.value
        #expect(await state.records.isEmpty)
        #expect(await state.sends == 0)
        #expect(try await service.retry(operationID: prepared.operationID) == .needsForeground)
    }

    @Test func coldLaunchReplayInvalidationPreservesOriginalUnknownOperation() async throws {
        let state = SafetyActionState(); let initialService = service(state)
        guard case let .ready(prepared) = try await initialService.prepare(input()) else { return }
        await state.setTransportFailure(true)
        #expect(try await initialService.execute(prepared) == .resultUnknown)
        let recoveredService = service(state)
        await state.configureInvalidationRace()
        let replay = Task { try await recoveredService.retry(operationID: prepared.operationID) }
        while !(await state.sendingSaveWaiting) { await Task.yield() }
        let invalidating = Task { try await recoveredService.invalidate(ownerUserID: "owner") }
        while !(await state.sendingSnapshotWaiting) { await Task.yield() }
        await state.releaseSendingSave()
        #expect(try await replay.value == .needsForeground)
        await state.releaseSnapshot()
        try await invalidating.value
        #expect(await state.records.count == 1)
        #expect(await state.records.first?.state == .resultUnknown)
        #expect(await state.records.first?.prepared == prepared)
        await state.setOwner("another")
        await #expect(throws: SystemActionAccessError.accountChanged) { try await recoveredService.retry(operationID: prepared.operationID) }
    }

    @Test func failedReplacementSavePreservesOriginalHandoffInput() async throws {
        let state = SafetyActionState(); let service = service(state)
        guard case let .ready(prepared) = try await service.prepare(input()) else { return }
        await state.setFailure(.response(422, nil))
        _ = try await service.execute(prepared)
        await state.failSave()
        var edited = input(); edited.end = now.addingTimeInterval(2700)
        await #expect(throws: URLError.self) { try await service.updateInput(operationID: prepared.operationID, input: edited) }
        #expect(await state.records.first?.input == prepared.input)
        #expect(await state.records.first?.operationID == prepared.operationID)
    }

}
