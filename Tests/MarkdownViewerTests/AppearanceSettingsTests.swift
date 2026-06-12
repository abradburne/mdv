import XCTest
@testable import mdv

final class AppearanceSettingsTests: XCTestCase {
    func testFontSizeCssOverridesRootFontSize() {
        XCTAssertEqual(AppModel.fontSizeCss(18), "html { font-size: 18px; }")
    }

    func testEffectiveFontSizeFallsBackToDefaultWhenUnset() {
        XCTAssertEqual(AppModel.effectiveFontSize(stored: 0), 16)
        XCTAssertEqual(AppModel.effectiveFontSize(stored: 21), 21)
    }

    // Regression: SettingsModel's CLI install helpers run on a background queue.
    // Before being marked nonisolated they inherited @MainActor isolation and
    // trapped with _dispatch_assert_queue_fail at runtime.
    func testCLIHelpersAreCallableOffTheMainActor() {
        let done = expectation(description: "ran off the main actor")
        DispatchQueue.global().async {
            _ = SettingsModel.cliScript(appPath: "/Applications/mdv.app")
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
