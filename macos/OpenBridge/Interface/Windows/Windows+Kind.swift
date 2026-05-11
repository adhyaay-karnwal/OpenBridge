//
//  Windows+Kind.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import Foundation

nonisolated extension Windows {
    nonisolated enum Kind: CaseIterable {
        case chat
        case backgroundTasks
        case settings
    }
}
