import Foundation

enum ReportReason: String, CaseIterable, Codable, Equatable, Sendable {
    case inappropriateName = "不適切な表示名"
    case nuisanceInvitation = "迷惑な招待"
    case impersonation = "なりすまし"
    case harassment = "嫌がらせ"
    case other = "その他"

    /// User-facing label. The raw value stays stable for persistence.
    var title: String {
        switch self {
        case .nuisanceInvitation: "迷惑なお誘い"
        default: rawValue
        }
    }
}

struct ReportReceipt: Equatable, Codable, Sendable {
    var reference: String
}

enum AccountDeletionStatus: Equatable, Sendable {
    case idle
    case accepted(reference: String)
    case processing(reference: String)
    case completed
    case actionRequired(reference: String, message: String)
}
