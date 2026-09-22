import Foundation
import Testing
@testable import Himatch

@Suite("Profile boundary")
struct ProfileBoundaryTests {
    @Test("Nickname is trimmed and limited to 20 characters")
    func nicknameValidation() throws {
        #expect(try ProfilePolicy.validatedNickname(" ひまり ") == "ひまり")
        #expect(throws: ProfileValidationError.invalidNickname) {
            try ProfilePolicy.validatedNickname("   ")
        }
        #expect(throws: ProfileValidationError.invalidNickname) {
            try ProfilePolicy.validatedNickname(String(repeating: "あ", count: 21))
        }
    }

    @Test("Only the four preset icons are accepted")
    func iconValidation() throws {
        #expect(PresetProfileIcon.allCases.count == 4)
        #expect(try ProfilePolicy.presetIcon("leaf.fill") == .leaf)
        #expect(throws: ProfileValidationError.invalidPresetIcon) {
            try ProfilePolicy.presetIcon("person.crop.circle")
        }
    }

    @Test("Generated Info.plist configuration rejects missing placeholders")
    func configurationValidation() throws {
        let configuration = try AppConfiguration(values: [
            "SUPABASE_URL": "https://project.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            "API_BASE_URL": "https://api.example.com/",
        ])

        #expect(configuration.supabaseURL.absoluteString == "https://project.supabase.co")
        #expect(configuration.supabasePublishableKey == "sb_publishable_test")
        #expect(throws: AppConfigurationError.missing("SUPABASE_URL")) {
            try AppConfiguration(values: [
                "SUPABASE_URL": "$(SUPABASE_URL)",
                "SUPABASE_PUBLISHABLE_KEY": "key",
                "API_BASE_URL": "https://api.example.com",
            ])
        }
    }
}
