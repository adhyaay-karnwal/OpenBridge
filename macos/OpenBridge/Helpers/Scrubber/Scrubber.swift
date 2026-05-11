//
//  Scrubber.swift
//  OpenBridge
//
//  Created by qaq on 19/11/2025.
//

import Foundation
import ScrubberKit
import WebKit

/*
 Task.detached {
     let content = try await ScrubberDispatcher.contentFrom(URL(string: "https://example.com")!)
     print(content)
 }
 */

@MainActor
enum ScrubberDispatcher {
    private static let setupBlock: Void = {
        Logger.scrubber.info("Setting up ScrubberKit dispatcher")
        ScrubberConfiguration.setup()
        return ()
    }()

    static func setup() {
        _ = setupBlock
    }

    static var webStorage: WKWebsiteDataStore {
        setup()
        return .init(forIdentifier: ScrubberConfiguration.storageIdentifier)
    }

    static func createWebView(_ setupConfiguration: (WKWebViewConfiguration) -> Void = { _ in }) -> WKWebView {
        setup()
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        setupConfiguration(config)
        config.websiteDataStore = webStorage
        let webView = WKWebView(frame: .init(), configuration: config)
        webView.customUserAgent = ScrubberConfiguration.desktopChromeUserAgent
        return webView
    }
}

nonisolated extension ScrubberDispatcher {
    nonisolated static func contentFrom(_ url: URL?, maxContentLength: Int = 32768) async throws -> Scrubber.Document {
        await ScrubberDispatcher.setup()

        return try await withCheckedThrowingContinuation { continuation in
            guard let url else {
                let error = NSError(domain: "Scrubber", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid URL"),
                ])
                continuation.resume(throwing: error)
                return
            }

            Task { @MainActor in
                Scrubber.document(for: url) { doc in
                    guard var doc else {
                        let error = NSError(domain: "Scrubber", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Failed to fetch the web content."),
                        ])
                        continuation.resume(throwing: error)
                        return
                    }

                    if doc.textDocument.count > maxContentLength {
                        var truncatedContent = doc.textDocument.prefix(maxContentLength)
                        truncatedContent += "..." + "\n" + String(localized: "Content truncated due to excessive length.")
                        doc = .init(
                            title: doc.title,
                            url: url,
                            document: doc.document,
                            textDocument: String(truncatedContent),
                            engine: doc.engine
                        )
                    }

                    continuation.resume(returning: doc)
                }
            }
        }
    }
}
