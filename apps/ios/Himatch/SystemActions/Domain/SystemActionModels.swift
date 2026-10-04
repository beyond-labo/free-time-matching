import Foundation

enum SystemActionKind: String, Codable, Sendable { case addAvailability, subtractAvailability, createHosting, cancelHosting }

struct SystemActionMetadata: Equatable, Codable, Sendable {
    var category: ActivityCategory? = nil
    var visibility: AvailabilityVisibility = .privateUntilAccepted
}

/// Only IDs and explicit input are persisted; display names and credentials are never journaled.
struct SystemActionInput: Equatable, Codable, Sendable {
    var kind: SystemActionKind
    var start: Date? = nil
    var end: Date? = nil
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var entityOwnerUserID: String? = nil
    var friendIDs: [UUID] = []
    var hostingID: UUID? = nil
    var mode: HostingMode? = nil
    var area: HostingArea? = nil
    var category: ActivityCategory? = nil
    var availabilityMetadata: SystemActionMetadata? = nil
}

struct PreparedSystemAction: Equatable, Codable, Sendable {
    var operationID: UUID
    var ownerUserID: String
    var input: SystemActionInput
    var expectedVersion: Int?
    var confirmationFingerprint: String
    var requiresConfirmation: Bool { input.kind == .createHosting || input.kind == .cancelHosting }
}

enum ActionPreparation: Equatable, Sendable {
    case ready(PreparedSystemAction)
    case needsMetadataSelection([SystemActionMetadata])
    case needsAuthentication
    case needsDisambiguation
    case invalidInput(String)
}

enum ActionOutcome: Equatable, Sendable {
    case completed
    case needsForeground
    case blockedByHosting
    case conflict
    case resultUnknown
    case failed(String)
}

enum SystemActionAccessError: Error, Equatable, Sendable {
    case protectedDataUnavailable, needsAuthentication, profileRequired, accountStopped, accountChanged
}

enum SystemActionRecordState: String, Codable, Sendable {
    case draft, prepared, awaitingForeground, sending, resultUnknown, conflict, completed
}

struct SystemActionRecord: Equatable, Codable, Identifiable, Sendable {
    var operationID: UUID
    var ownerUserID: String?
    var input: SystemActionInput
    var expectedVersion: Int? = nil
    var confirmationFingerprint: String? = nil
    var state: SystemActionRecordState
    var createdAt: Date
    var id: UUID { operationID }
    var prepared: PreparedSystemAction? {
        guard let ownerUserID, let confirmationFingerprint else { return nil }
        return PreparedSystemAction(operationID: operationID, ownerUserID: ownerUserID, input: input,
                                    expectedVersion: expectedVersion, confirmationFingerprint: confirmationFingerprint)
    }
}

typealias SystemActionHandoff = SystemActionRecord
