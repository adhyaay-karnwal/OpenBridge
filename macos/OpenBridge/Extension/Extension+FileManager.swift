//
//  Extension+FileManager.swift
//  OpenBridge
//
//  Created by 秋星桥 on 2025/12/26.
//

import Foundation

extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}
