@testable import OpenBridge
import Foundation
import Testing

struct AppRequestDetectorTests {
    @Test
    func `recognized location tag at start of message returns location kind`() {
        let text = "<app-request type=\"location\" />\nI'll check the weather for you."
        #expect(AppRequestDetector.detect(in: text) == .location)
    }

    @Test
    func `leading whitespace before the tag still matches`() {
        let text = "   <app-request type=\"location\" />\nHello"
        #expect(AppRequestDetector.detect(in: text) == .location)
    }

    @Test
    func `tag not at the start of text is not detected`() {
        let text = "Hi there! <app-request type=\"location\" />"
        #expect(AppRequestDetector.detect(in: text) == nil)
    }

    @Test
    func `unknown request type returns nil without throwing`() {
        let text = "<app-request type=\"camera\" />\nSmile!"
        #expect(AppRequestDetector.detect(in: text) == nil)
    }

    @Test
    func `partial tag during streaming is not detected`() {
        let partials = [
            "<",
            "<app-request",
            "<app-request type=\"loc",
            "<app-request type=\"location\"",
            "<app-request type=\"location\" /",
        ]
        for partial in partials {
            #expect(AppRequestDetector.detect(in: partial) == nil, "should not detect from '\(partial)'")
        }
    }

    @Test
    func `empty text returns nil`() {
        #expect(AppRequestDetector.detect(in: "") == nil)
    }

    @Test
    func `tag with extra whitespace between attribute and slash is detected`() {
        let text = "<app-request   type=\"location\"   />\nContinuing..."
        #expect(AppRequestDetector.detect(in: text) == .location)
    }

    @Test
    func `tag with empty type attribute is not detected`() {
        let text = "<app-request type=\"\" />\n"
        #expect(AppRequestDetector.detect(in: text) == nil)
    }
}
