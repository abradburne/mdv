import XCTest
@testable import mdv

@MainActor
final class SettingsModelCLITests: XCTestCase {
    func testResolvedAppBundleURLUsesBundleURLWhenItIsAnAppBundle() {
        let appURL = URL(fileURLWithPath: "/Applications/mdv.app")
        let resolved = SettingsModel.resolvedAppBundleURL(
            bundleURL: appURL,
            workspaceLookup: { _ in nil }
        )
        XCTAssertEqual(resolved, appURL)
    }

    func testResolvedAppBundleURLFallsBackToWorkspaceLookupForDevBuilds() {
        let debugDir = URL(fileURLWithPath: "/Users/alan/project/.build/arm64-apple-macosx/debug")
        let installedApp = URL(fileURLWithPath: "/Applications/mdv.app")
        let resolved = SettingsModel.resolvedAppBundleURL(
            bundleURL: debugDir,
            workspaceLookup: { identifier in
                identifier == "jp.co.xenocode.mdv" ? installedApp : nil
            }
        )
        XCTAssertEqual(resolved, installedApp)
    }

    func testResolvedAppBundleURLReturnsNilWhenNoAppBundleFound() {
        let debugDir = URL(fileURLWithPath: "/Users/alan/project/.build/arm64-apple-macosx/debug")
        let resolved = SettingsModel.resolvedAppBundleURL(
            bundleURL: debugDir,
            workspaceLookup: { _ in nil }
        )
        XCTAssertNil(resolved)
    }

    func testCLIScriptLaunchesResolvedAppAndSurfacesErrors() {
        let script = SettingsModel.cliScript(appPath: "/Applications/mdv.app")
        XCTAssertTrue(script.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(script.contains("open -a \"/Applications/mdv.app\" \"$@\""))
        XCTAssertFalse(script.contains(" -g "), "-g keeps the app in the background; the window should come to the front")
        XCTAssertFalse(script.contains("nohup"), "nohup + /dev/null hides launch errors from the user")
        XCTAssertFalse(script.contains("/dev/null"), "errors should be visible in the terminal")
    }
}
