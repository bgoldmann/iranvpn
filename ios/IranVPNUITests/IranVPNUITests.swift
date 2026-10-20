import XCTest

final class IranVPNUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsConnectOrDisclaimer() throws {
        let app = XCUIApplication()
        app.launch()

        let accept = app.buttons["می‌پذیرم / I understand and accept the risks"]
        if accept.waitForExistence(timeout: 8) {
            accept.tap()
        }

        // Tab bar Connect destination, or Connect button on Connect tab.
        let connectTab = app.tabBars.buttons["اتصال / Connect"]
        let connectButton = app.buttons["اتصال / Connect"]
        let disconnect = app.buttons["قطع اتصال / Disconnect"]
        let cancel = app.buttons["لغو / Cancel"]

        let landed = connectTab.waitForExistence(timeout: 6)
            || connectButton.waitForExistence(timeout: 2)
            || disconnect.waitForExistence(timeout: 1)
            || cancel.waitForExistence(timeout: 1)
        XCTAssertTrue(landed, "Expected Connect tab or Connect controls after launch")

        if connectTab.exists {
            connectTab.tap()
        }
        XCTAssertTrue(
            connectButton.exists || disconnect.exists || cancel.exists
                || app.staticTexts["Iran VPN"].exists,
            "Connect tab should show brand or connect controls"
        )
    }
}
