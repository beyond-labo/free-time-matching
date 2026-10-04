import Foundation
import Observation

extension Notification.Name {
    static let systemActionRequested = Notification.Name("Himatch.systemActionRequested")
}

@MainActor
@Observable
final class SystemActionHandoffCoordinator {
    private(set) var requestedOperationID: UUID?

    func request(_ operationID: UUID) {
        requestedOperationID = operationID
        NotificationCenter.default.post(name: .systemActionRequested, object: nil)
    }
}

struct SystemActionHandoffClient: Sendable {
    var pendingOperationID: @Sendable () async -> UUID?
    var invalidate: @Sendable (String) async -> Void
    static let noop = Self(pendingOperationID: { nil }, invalidate: { _ in })
}
