import WebKit

extension WKWebView {
    @MainActor
    func evaluateJavaScriptAsync(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            self.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    nonisolated(unsafe) let unsafeResult = result
                    continuation.resume(returning: unsafeResult)
                }
            }
        }
    }
}
