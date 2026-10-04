import Foundation

actor SystemActionJournal {
    private let directory: URL
    init(directory: URL) { self.directory = directory }

    nonisolated var client: SystemActionJournalClient {
        SystemActionJournalClient(records: { try await self.records() },
                                  save: { try await self.save($0) }, remove: { try await self.remove($0) })
    }

    func records() throws -> [SystemActionRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var records: [SystemActionRecord] = []
        for file in files where file.pathExtension == "json" {
            // IO/protection failures must propagate; malformed content is isolated per file.
            let data = try Data(contentsOf: file)
            do { records.append(try JSONDecoder().decode(SystemActionRecord.self, from: data)) }
            catch is DecodingError {
                let isolated = file.deletingPathExtension().appendingPathExtension("corrupt")
                try FileManager.default.moveItem(at: file, to: isolated)
            }
        }
        return records.sorted { $0.createdAt == $1.createdAt ? $0.operationID.uuidString < $1.operationID.uuidString : $0.createdAt < $1.createdAt }
    }

    func save(_ record: SystemActionRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var location = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        try JSONEncoder().encode(record).write(to: url(record.operationID), options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(record).write(to: url(record.operationID), options: .atomic)
        #endif
    }

    func remove(_ id: UUID) throws {
        let file = url(id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
