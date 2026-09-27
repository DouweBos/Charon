// CharonUITestsLaunchTests.swift
// CharonUITests

import XCTest

final class CharonUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTabs() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Analyze"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Offload"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
