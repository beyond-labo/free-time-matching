import Foundation

struct AppConfiguration: Equatable, Sendable {
    let supabaseURL: URL
    let supabasePublishableKey: String
    let apiBaseURL: URL

    init(bundle: Bundle = .main) throws {
        try self.init(values: bundle.infoDictionary ?? [:])
    }

    init(values: [String: Any]) throws {
        supabaseURL = try Self.url(key: "SUPABASE_URL", values: values)
        supabasePublishableKey = try Self.string(key: "SUPABASE_PUBLISHABLE_KEY", values: values)
        apiBaseURL = try Self.url(key: "API_BASE_URL", values: values)
    }

    private static func string(key: String, values: [String: Any]) throws -> String {
        guard
            let raw = values[key] as? String,
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !raw.contains("$(")
        else { throw AppConfigurationError.missing(key) }
        return raw
    }

    private static func url(key: String, values: [String: Any]) throws -> URL {
        let value = try string(key: key, values: values)
        guard let url = URL(string: value), let scheme = url.scheme, allowedURLSchemes.contains(scheme) else {
            throw AppConfigurationError.invalidURL(key)
        }
        return url
    }

    private static var allowedURLSchemes: Set<String> {
#if DEBUG
        ["http", "https"]
#else
        ["https"]
#endif
    }
}

enum AppConfigurationError: LocalizedError, Equatable, Sendable {
    case missing(String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case let .missing(key):
            "アプリ設定 \(key) がありません。ビルド設定を確認してください。"
        case let .invalidURL(key):
            "アプリ設定 \(key) のURLが正しくありません。"
        }
    }
}
