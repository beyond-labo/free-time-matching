import AppIntents
import Foundation

struct CreateHostingIntent: SystemActionIntent {
    // Declare on each concrete intent so Apple's metadata extractor sees the policy.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static let title: LocalizedStringResource = "友達を誘う"
    static let description = IntentDescription("日時と開催条件をまとめて確認して、友達への募集を作成します。")
    @Parameter(title: "開始日時") var start: Date
    @Parameter(title: "終了日時") var end: Date
    @Parameter(title: "誘う友達") var friends: [FriendEntity]
    @Parameter(title: "開催形態") var mode: SystemHostingMode
    @Parameter(title: "カテゴリ") var category: SystemActivityCategory?
    @Parameter(title: "エリア") var area: SystemHostingArea?
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, SystemHostingMode.offline) {
            Summary("\(\.$start)から\(\.$end)に\(\.$friends)を\(\.$mode)で誘う") {
                \.$category
                \.$area
            }
        } otherwise: {
            Summary("\(\.$start)から\(\.$end)に\(\.$friends)を\(\.$mode)で誘う") {
                \.$category
            }
        }
    }
    func dateParameterError(_ issue: SystemActionDateIssue) -> Error {
        let dialog = IntentDialog(stringLiteral: issue.message)
        switch issue {
        case .start: return $start.needsValueError(dialog)
        case .end: return $end.needsValueError(dialog)
        }
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Set(friends.map(\.ownerUserID)).count <= 1 else {
            return .result(dialog: "友達を現在のアカウントで選び直してください。")
        }
        let input = SystemActionInput(kind: .createHosting, start: start, end: end,
            entityOwnerUserID: friends.first?.ownerUserID, friendIDs: friends.map(\.userID),
            mode: mode.domainValue, area: mode == .offline ? (area?.domainValue ?? .discussLater) : nil,
            category: category?.domainValue)
        let message = try await run(input, operationID: operationID, friends: friends)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct CancelHostingIntent: SystemActionIntent {
    // Declare on each concrete intent so Apple's metadata extractor sees the policy.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static let title: LocalizedStringResource = "募集を取り消す"
    static let description = IntentDescription("本人の募集中の募集を確認して取り消します。")
    @Parameter(title: "取り消す募集") var hosting: OwnedHostingEntity
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary { Summary("\(\.$hosting)を取り消す") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Cached entity dates and version are not authoritative; prepare fetches the current hosting.
        let input = SystemActionInput(kind: .cancelHosting, entityOwnerUserID: hosting.ownerUserID, hostingID: hosting.hostingID)
        let message = try await run(input, operationID: operationID)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
