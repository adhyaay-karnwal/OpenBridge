//
//  Scrubber+Utils.swift
//  Playground
//
//  Created by 秋星桥 on 2/17/25.
//

import Foundation

extension Scrubber {
    func scrub(url: URL, retry: Int, completion: @escaping (ScrubWorker.ScrubResult?) -> Void) {
        assert(!Thread.isMainThread)

        var completionIsCalled = false
        let completion: (ScrubWorker.ScrubResult?) -> Void = { result in
            guard !completionIsCalled else { return }
            completionIsCalled = true
            completion(result)
        }
        defer { completion(nil) }

        var round = 0
        while retry > round, !isCancelled, !completionIsCalled {
            round += 1
            let semaphore = DispatchSemaphore(value: 0)
            scrub(url: url) { result in
                defer { semaphore.signal() }
                guard let result else { return }
                completion(result)
            }
            let isTimeOut = semaphore.wait(timeout: .now() + timeout)
            if isTimeOut == .timedOut { return }
        }
    }

    func scrub(url: URL, completion: @escaping (ScrubWorker.ScrubResult?) -> Void) {
        assert(!Thread.isMainThread)
        guard !isCancelled else { return }

        var isCompletionCalled = false
        let completion = { result in
            guard !isCompletionCalled else { return }
            isCompletionCalled = true
            DispatchQueue.global().async { completion(result) }
        }

        DispatchQueue.main.async {
            self.dispatchWorker(retrievingURL: url, onComplete: completion)
        }
    }
}
