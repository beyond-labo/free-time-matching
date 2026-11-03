import Foundation

struct AutomaticSchedulingUseCase: Sendable {
    let repository: AutomaticSchedulingRepository

    func load(token: String) async throws -> SchedulingSnapshot { try await repository.load(token) }
    func execute(_ command: SchedulingCommand, operationID: UUID, token: String) async throws -> SchedulingSnapshot {
        try await repository.execute(command, operationID, token)
    }
    func registerDevice(token: String, environment: String, enabled: Bool, accessToken: String) async throws -> SchedulingSnapshot {
        try await repository.registerDevice(token, environment, enabled, accessToken)
    }
}
