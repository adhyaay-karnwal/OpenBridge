//
//  OpenBridgeUITestsLaunchTests.swift
//  OpenBridgeUITests
//
//  Created by qaq on 16/10/2025.
//

import XCTest

final class OpenBridgeUITestsLaunchTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testLaunchAndExecuteScreenshotOnAll() throws {
        let app = try XCTUnwrap(app)
        app.launch()

        _ = app.waitForExistence(timeout: 10)

        let windows = app.windows

        for (index, window) in windows.allElementsBoundByIndex.enumerated() {
            let windowName = window.title.isEmpty ? "Window \(index + 1)" : window.title

            let screenshot = app.windows.element(boundBy: index).screenshot()
            let attachment: XCTAttachment = .init(screenshot: screenshot)
            attachment.name = windowName
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        app.terminate()
    }
}
