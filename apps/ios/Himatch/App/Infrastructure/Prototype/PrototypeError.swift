import Foundation

/// Errors of the DEBUG prototype scenario. Kept in Release because the unconfigured placeholder client reuses them.
enum PrototypeError: LocalizedError, Equatable, Sendable {
    case invalidDisplayName
    case friendRequired
    case areaRequired
    case noCommonTime
    case noParticipantResponse
    case notFound
    case noteTooLong

    var errorDescription: String? {
        switch self {
        case .invalidDisplayName: "表示名は1〜20文字で入力してください。"
        case .friendRequired: "友達を1人以上選んでください。"
        case .areaRequired: "オフラインではエリアを選んでください。"
        case .noCommonTime: "全員が参加できる時間がまだありません。"
        case .noParticipantResponse: "参加OKの回答がまだありません。"
        case .notFound: "最新の状態を取得できませんでした。"
        case .noteTooLong: "補足は500文字以内で入力してください。"
        }
    }
}
