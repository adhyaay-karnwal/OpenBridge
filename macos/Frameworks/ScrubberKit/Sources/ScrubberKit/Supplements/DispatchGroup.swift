//
//  DispatchGroup.swift
//  ScrubberKit
//
//  Created by 秋星桥 on 2/18/25.
//

import Foundation

extension DispatchGroup {
    typealias LeaveHandler = () -> Void
    typealias LeaveHandlerFunc = (@escaping LeaveHandler) -> Void

    func enterBackground(_ leaveHandlerFunc: @escaping LeaveHandlerFunc) {
        enter()

        DispatchQueue.global().async {
            var hasLeft = false

            leaveHandlerFunc {
                guard !hasLeft else {
                    assertionFailure()
                    return
                }

                hasLeft = true
                self.leave()
            }
        }
    }
}
