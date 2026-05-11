//
//  TokenBox.swift
//  OpenBridge
//
//  Created by qaq on 18/11/2025.
//

import Foundation

nonisolated class TokenBox: @unchecked Sendable {
    var token: UUID = .init()

    nonisolated func rotate() -> UUID {
        let newToken = UUID()
        token = newToken
        return token
    }

    nonisolated func isValid(token: UUID) -> Bool {
        self.token == token
    }
}
