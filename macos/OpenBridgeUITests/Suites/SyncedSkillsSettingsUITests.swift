import AppKit
import XCTest

final class SyncedSkillsSettingsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var e2eHomeDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        e2eHomeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenBridgeSyncedSkillsUITests-\(UUID().uuidString)", isDirectory: true)
        try createSuggestedSkillFolders(in: e2eHomeDirectory)

        app = XCUIApplication()
        app.launchArguments = ["-e2eMode", "-e2eOpenSettings", "-e2eResetAccentColor"]
        app.launchEnvironment["OPENBRIDGE_E2E_HOME_DIRECTORY"] = e2eHomeDirectory.path
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let e2eHomeDirectory {
            try? FileManager.default.removeItem(at: e2eHomeDirectory)
        }
    }

    func testSuggestedAddButtonUsesVisibleAccentTint() throws {
        openSyncedSkillsSettings()

        let addButton = app.buttons["settings.syncedSkills.suggested.add.claude"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))

        let screenshot = addButton.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Suggested Add Button"
        attachment.lifetime = .keepAlways
        add(attachment)

        let color = try averageOpaqueColor(in: screenshot.pngRepresentation)
        XCTAssertGreaterThan(color.maxComponent, 60, "Suggested Add button should not render as a near-black block.")
        XCTAssertGreaterThan(color.luminance, 40, "Suggested Add button should keep enough visible fill contrast.")

        addButton.click()
        XCTAssertFalse(addButton.waitForExistence(timeout: 3))
    }

    private func createSuggestedSkillFolders(in homeDirectory: URL) throws {
        let fileManager = FileManager.default
        for relativePath in [".claude/skills", ".codex/skills"] {
            let url = homeDirectory.appendingPathComponent(relativePath, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func openSyncedSkillsSettings() {
        let settingsWindow = app.windows["Settings"].firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        let tabByIdentifier = app.descendants(matching: .any)["settings.tab.syncedSkills"].firstMatch
        if tabByIdentifier.waitForExistence(timeout: 3) {
            tabByIdentifier.click()
            return
        }

        let tabByTitle = app.staticTexts["Synced Skills"].firstMatch
        XCTAssertTrue(tabByTitle.waitForExistence(timeout: 3))
        tabByTitle.click()
    }

    private func averageOpaqueColor(in pngData: Data) throws -> AverageColor {
        guard let image = NSImage(data: pngData) else {
            throw ColorSamplingError.invalidImage
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw ColorSamplingError.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw ColorSamplingError.invalidImage
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            guard pixels[offset + 3] > 32 else { continue }
            red += Double(pixels[offset])
            green += Double(pixels[offset + 1])
            blue += Double(pixels[offset + 2])
            count += 1
        }

        guard count > 0 else {
            throw ColorSamplingError.noOpaquePixels
        }

        return AverageColor(red: red / count, green: green / count, blue: blue / count)
    }
}

private struct AverageColor {
    let red: Double
    let green: Double
    let blue: Double

    var maxComponent: Double {
        max(red, green, blue)
    }

    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

private enum ColorSamplingError: Error {
    case invalidImage
    case noOpaquePixels
}
