import Foundation
import Testing
@testable import Himatch

@Suite("Himatch app")
@MainActor
struct HimatchTests {
    @Test("表示名はアイマノ")
    func displayName() {
        #expect(HimatchApp.displayName == "アイマノ")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "アイマノ")
    }

    @Test("Bundle IDはcom.beyond-labo.aimano")
    func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.beyond-labo.aimano")
    }
}
