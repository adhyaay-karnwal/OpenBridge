//
//  RuntimeError.swift
//  OpenBridge
//
//  Created by EYHN on 2025/11/26.
//

struct RuntimeError: LocalizedError {
    var errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }

    init(localized: LocalizedStringResource) {
        errorDescription = String(localized: localized)
    }
}
