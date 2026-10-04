import AppIntents
import Foundation

struct AddAvailabilityIntent: SystemActionIntent {
    // Declare on each concrete intent so Apple's metadata extractor sees the policy.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static let title: LocalizedStringResource = "暇を登録"
    static let description = IntentDescription("指定した開始・終了日時の暇を登録します。")
    @Parameter(title: "開始日時") var start: Date
    @Parameter(title: "終了日時") var end: Date
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary { Summary("\(\.$start)から\(\.$end)の暇を登録") }
    func dateParameterError(_ issue: SystemActionDateIssue) -> Error {
        let dialog = IntentDialog(stringLiteral: issue.message)
        switch issue {
        case .start: return $start.needsValueError(dialog)
        case .end: return $end.needsValueError(dialog)
        }
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await run(SystemActionInput(kind: .addAvailability, start: start, end: end), operationID: operationID)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct SubtractAvailabilityIntent: SystemActionIntent {
    // Declare on each concrete intent so Apple's metadata extractor sees the policy.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static let title: LocalizedStringResource = "暇を削除"
    static let description = IntentDescription("指定した開始・終了日時の暇を削除します。")
    @Parameter(title: "開始日時") var start: Date
    @Parameter(title: "終了日時") var end: Date
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary { Summary("\(\.$start)から\(\.$end)の暇を削除") }
    func dateParameterError(_ issue: SystemActionDateIssue) -> Error {
        let dialog = IntentDialog(stringLiteral: issue.message)
        switch issue {
        case .start: return $start.needsValueError(dialog)
        case .end: return $end.needsValueError(dialog)
        }
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await run(SystemActionInput(kind: .subtractAvailability, start: start, end: end), operationID: operationID)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
