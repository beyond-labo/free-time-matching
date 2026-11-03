import Foundation

struct AutomaticSchedulingRepository: Sendable {
    var load: @Sendable (String) async throws -> SchedulingSnapshot
    var execute: @Sendable (SchedulingCommand, UUID, String) async throws -> SchedulingSnapshot
    var registerDevice: @Sendable (String, String, Bool, String) async throws -> SchedulingSnapshot
}
