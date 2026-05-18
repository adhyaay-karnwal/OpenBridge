//
//  MainWindowUITests.swift
//  OpenBridgeUITests
//
//  Created by GPT-5 Codex on 06/12/2025.
//

import AppKit
import XCTest

final class MainWindowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-e2eMode")
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

    func testPanelNewChatButtonHoverShowsVisualFeedback() throws {
        let window = waitForMainWindow()
        let newChatButton = waitForHittableButton(
            identifier: "chat.header.newChatButton",
            fallbackNames: ["New Chat", "Add"]
        )
        XCTAssertTrue(newChatButton.isHittable)

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.9)).hover()
        Thread.sleep(forTimeInterval: 0.2)
        let unhovered = newChatButton.screenshot()

        newChatButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        Thread.sleep(forTimeInterval: 0.2)
        let hovered = newChatButton.screenshot()

        let delta = try HoverScreenshotDelta.measure(before: unhovered, after: hovered)
        XCTAssertGreaterThan(delta.changedPixelCount, 12)
        XCTAssertGreaterThan(delta.averageChannelDelta, 0.2)

        attach(window: window, name: "Panel New Chat Hover")
    }

    private func waitForHittableButton(
        identifier: String,
        fallbackNames: [String] = [],
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        let identifierButtons = app.buttons.matching(identifier: identifier)

        repeat {
            if let button = identifierButtons.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return button
            }
            for name in fallbackNames {
                let button = app.buttons[name].firstMatch
                if button.exists, button.isHittable {
                    return button
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let fallback = identifierButtons.firstMatch
        XCTAssertTrue(fallback.exists, "Expected hittable button with identifier \(identifier)")
        XCTAssertTrue(fallback.isHittable, "Expected hittable button with identifier \(identifier)")
        return fallback
    }
}

private struct HoverScreenshotDelta {
    let changedPixelCount: Int
    let averageChannelDelta: Double

    static func measure(
        before: XCUIScreenshot,
        after: XCUIScreenshot
    ) throws -> HoverScreenshotDelta {
        let beforeImage = try bitmap(from: before)
        let afterImage = try bitmap(from: after)
        let sampleWidth = max(beforeImage.pixelsWide, afterImage.pixelsWide)
        let sampleHeight = max(beforeImage.pixelsHigh, afterImage.pixelsHigh)
        let beforeOffsetX = (sampleWidth - beforeImage.pixelsWide) / 2
        let beforeOffsetY = (sampleHeight - beforeImage.pixelsHigh) / 2
        let afterOffsetX = (sampleWidth - afterImage.pixelsWide) / 2
        let afterOffsetY = (sampleHeight - afterImage.pixelsHigh) / 2

        var changedPixels = 0
        var totalDelta = 0.0
        var sampleCount = 0

        for y in 0 ..< sampleHeight {
            for x in 0 ..< sampleWidth {
                let beforeColor = deviceRGBColor(
                    atX: x - beforeOffsetX,
                    y: y - beforeOffsetY,
                    in: beforeImage
                )
                let afterColor = deviceRGBColor(
                    atX: x - afterOffsetX,
                    y: y - afterOffsetY,
                    in: afterImage
                )
                let delta = channelDelta(beforeColor, afterColor)
                totalDelta += delta
                sampleCount += 1
                if delta > 1.0 {
                    changedPixels += 1
                }
            }
        }

        return HoverScreenshotDelta(
            changedPixelCount: changedPixels,
            averageChannelDelta: sampleCount == 0 ? 0 : totalDelta / Double(sampleCount)
        )
    }

    private static func bitmap(from screenshot: XCUIScreenshot) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: screenshot.pngRepresentation))
    }

    private static func deviceRGBColor(atX x: Int, y: Int, in image: NSBitmapImageRep) -> NSColor? {
        guard x >= 0, y >= 0, x < image.pixelsWide, y < image.pixelsHigh else {
            return nil
        }
        return image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    private static func channelDelta(_ before: NSColor?, _ after: NSColor?) -> Double {
        switch (before, after) {
        case (.none, .none):
            return 0
        case (.none, .some), (.some, .none):
            return 255
        case let (.some(before), .some(after)):
            let red = abs(before.redComponent - after.redComponent)
            let green = abs(before.greenComponent - after.greenComponent)
            let blue = abs(before.blueComponent - after.blueComponent)
            return Double((red + green + blue) * 255 / 3)
        }
    }
}
