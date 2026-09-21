import Testing
@testable import Himatch

@Suite("Himatch app")
@MainActor
struct HimatchTests {
    @Test("表示名はひまっち")
    func displayName() {
        #expect(HimatchApp.displayName == "ひまっち")
    }
}
