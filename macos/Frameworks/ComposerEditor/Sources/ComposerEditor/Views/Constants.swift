//
//  Constants.swift
//  ComposerEditor
//

import Foundation

enum ComposerLayout {
    static let previewSize: CGFloat = 56
    static let filePreviewWidth: CGFloat = 140
}

enum ComposerControlStyle {
    static let disabledForegroundOpacity: Double = 0.4

    static func backgroundOpacity(isDarkMode: Bool, isActive: Bool, isDisabled: Bool) -> Double {
        if isDisabled {
            return isDarkMode ? 0.08 : 0.04
        }
        if isActive {
            return isDarkMode ? 0.20 : 0.12
        }
        return isDarkMode ? 0.15 : 0.08
    }
}
