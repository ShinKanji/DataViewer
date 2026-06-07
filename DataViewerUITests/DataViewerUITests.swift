import XCTest

final class DataViewerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchWithFixtureData() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        if let testData = ProcessInfo.processInfo.environment["TESTDATA_DIR"] {
            app.launchEnvironment["TESTDATA_DIR"] = testData
        }
        app.launch()

        let ready = app.descendants(matching: .any)["uiTestFixturesReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 30))
    }
}
