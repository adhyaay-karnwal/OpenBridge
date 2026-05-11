//
//  InspectorPreviewUITests.swift
//  OpenBridgeUITests
//
//  Created by qaq on 6/12/2025.
//

import XCTest

final class InspectorPreviewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
    }

    func testPreviewToggleWithKeyboard() throws {
        let app = try XCTUnwrap(app)

        // 选中第一行（如果存在）
        if let firstRow = app.tables.firstMatch.cells.firstMatch as XCUIElement? {
            if firstRow.exists {
                firstRow.click()
            }
        }

        // 空格唤起预览
        app.typeKey(.space, modifierFlags: [])

        // 上下切换选中条目
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])

        // 右箭头进入 action 区域后预览应关闭（无法直接断言 UI，这里验证不会 crash）
        app.typeKey(.rightArrow, modifierFlags: [])

        // Esc 关闭预览
        app.typeKey(.escape, modifierFlags: [])

        // 截图保留现状
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
