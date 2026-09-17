import XCTest
@testable import Himatch

final class HimatchTests: XCTestCase {
    func testDisplayName() {
        XCTAssertEqual(HimatchApp.displayName, "ひまっち")
    }
}
