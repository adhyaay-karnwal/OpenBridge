//
//  MainWindowUITests.swift
//  OpenBridgeUITests
//
//  Created by GPT-5 Codex on 06/12/2025.
//

import XCTest

final class MainWindowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    @discardableResult
    private func waitForMainWindow(timeout: TimeInterval = 8) -> XCUIElement {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout))
        return window
    }

    private func attach(window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
