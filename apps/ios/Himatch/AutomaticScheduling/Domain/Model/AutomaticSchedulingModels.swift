import Foundation

struct SchedulingPeer: Equatable, Codable, Sendable {
    let userId: UUID
    let nickname: String
    let presetIconKey: String
}

struct SchedulingFeedback: Equatable, Codable, Sendable {
    var played: Bool
    var bothersome: Bool
    var privacyConcern: Bool
}

struct SchedulingProposal: Equatable, Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case pending, confirmed, declined, expired, cancelled }
    enum Response: String, Codable, Sendable { case pending, accepted, declined }
    let id: UUID
    let start: Date
    let end: Date
    let status: Status
    let myResponse: Response
    let version: Int
    let shareAcceptance: Bool
    let peer: SchedulingPeer?
    let peerResponse: Response?
    let feedback: SchedulingFeedback?
    var interval: TimeIntervalRange { .init(id: id, start: start, end: end) }
    /// An accepted answer is withdrawn by cancelling the proposal, never by answering twice.
    var withdrawalCommand: SchedulingCommand? {
        guard status == .pending, myResponse == .accepted else { return nil }
        return .cancel(id, version: version)
    }
}

struct SchedulingPermission: Equatable, Codable, Sendable {
    let friendId: UUID
    let enabled: Bool
}

struct SchedulingNotification: Equatable, Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case proposal, confirmed, cancelled }
    let id: UUID
    let proposalId: UUID
    let kind: Kind
    let createdAt: Date
}

struct SchedulingSnapshot: Equatable, Codable, Sendable {
    var enabled: Bool
    var permissions: [SchedulingPermission]
    var proposals: [SchedulingProposal]
    var notifications: [SchedulingNotification]
    static let empty = Self(enabled: false, permissions: [], proposals: [], notifications: [])
    func permits(_ friendID: UUID) -> Bool { permissions.first { $0.friendId == friendID }?.enabled ?? false }
}

enum SchedulingCommand: Equatable, Sendable {
    case settings(Bool)
    case permission(UUID, Bool)
    case response(UUID, SchedulingProposal.Response, shareAcceptance: Bool, version: Int)
    case cancel(UUID, version: Int)
    case feedback(UUID, SchedulingFeedback)
    case blockFriend(UUID)
    case blockProposal(UUID)
    case report(UUID, ReportReason)
    case reportFriend(UUID, ReportReason)
    enum ReportReason: String, CaseIterable, Sendable { case spam, harassment, other }
}

enum SchedulingFailure: Error, LocalizedError, Equatable, Sendable {
    case unauthorized, conflict, unavailable, invalidResponse, rejected
    var errorDescription: String? {
        switch self {
        case .unauthorized: "サインインし直してください。"
        case .conflict: "状態が変わりました。最新の内容をご確認ください。"
        case .unavailable: "通信結果を確認できませんでした。同じ操作で再試行できます。"
        case .invalidResponse: "応答を確認できませんでした。再読み込みしてください。"
        case .rejected: "この操作は現在利用できません。最新の内容をご確認ください。"
        }
    }
}
