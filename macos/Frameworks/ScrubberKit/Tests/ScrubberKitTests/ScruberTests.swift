import Foundation
@testable @preconcurrency import ScrubberKit
import Testing

@Test func search() async {
    await withCheckedContinuation { continuation in
        let scrubber = Scrubber(query: "Asspp")
        DispatchQueue.main.async {
            scrubber.run { result in
                #expect(!result.isEmpty)
                print("[*] searching \(scrubber.query) returns \(result.count) results")
                for doc in result {
                    print("[*] \(doc.title)")
                }
                continuation.resume()
            } onProgress: { progress in
                print("[*] \(progress)")
            }
        }
    }
}
