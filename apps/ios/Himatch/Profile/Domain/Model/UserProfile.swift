import Foundation

enum PresetProfileIcon: String, CaseIterable, Codable, Equatable, Sendable {
    case sun = "sun.max.fill"
    case leaf = "leaf.fill"
    case game = "gamecontroller.fill"
    case running = "figure.run"
}

struct UserProfile: Equatable, Sendable {
    let userID: String
    var nickname: String
    var presetIcon: PresetProfileIcon
}

enum ProfileValidationError: LocalizedError, Equatable, Sendable {
    case invalidNickname
    case invalidPresetIcon

    var errorDescription: String? {
        switch self {
        case .invalidNickname:
            "表示名は1〜20文字で入力してください。"
        case .invalidPresetIcon:
            "選択できるアイコンを指定してください。"
        }
    }
}

enum ProfilePolicy {
    static func validatedNickname(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...20).contains(normalized.count) else {
            throw ProfileValidationError.invalidNickname
        }
        return normalized
    }

    static func presetIcon(_ key: String) throws -> PresetProfileIcon {
        guard let icon = PresetProfileIcon(rawValue: key) else {
            throw ProfileValidationError.invalidPresetIcon
        }
        return icon
    }
}
