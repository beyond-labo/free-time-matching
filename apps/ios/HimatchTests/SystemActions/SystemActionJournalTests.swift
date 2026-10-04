import Foundation
import Testing
@testable import Himatch

struct SystemActionJournalTests {
    @Test func durableRecordRestoresOnlyExplicitInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SystemActionJournal(directory: directory)
        let record = SystemActionRecord(operationID: UUID(), ownerUserID: "owner", input: .init(kind: .createHosting, friendIDs: [UUID()], mode: .online), state: .sending, createdAt: Date())
        try await journal.save(record)
        let restored = try await SystemActionJournal(directory: directory).records()
        #expect(restored == [record])
        let data = try Data(contentsOf: directory.appendingPathComponent(record.id.uuidString).appendingPathExtension("json"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("displayName"))
        #expect(!text.contains("accessToken"))
        try await journal.remove(record.id)
        #expect(try await journal.records().isEmpty)
    }
    @Test func malformedFileIsIsolatedWithoutHidingValidPendingRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SystemActionJournal(directory: directory)
        let valid = SystemActionRecord(operationID: UUID(), ownerUserID: "owner", input: .init(kind: .addAvailability), state: .awaitingForeground, createdAt: Date())
        try await journal.save(valid)
        let malformed = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try Data("{broken".utf8).write(to: malformed)
        #expect(try await journal.records() == [valid])
        #expect(!FileManager.default.fileExists(atPath: malformed.path))
        #expect(FileManager.default.fileExists(atPath: malformed.deletingPathExtension().appendingPathExtension("corrupt").path))
        #expect(try await journal.records() == [valid])
    }

}
