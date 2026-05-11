//
//  Extension+NSFont.swift
//  OpenBridge
//
//  Created by qaq on 13/11/2025.
//

import AppKit

extension NSFont {
    var defaultLineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }

    // MARK: - App Typography

    /// Content font for primary text: cells, search bar, text views
    /// Uses .body text style
    static var content: NSFont {
        .systemFont(ofSize: 15, weight: .regular)
    }

    /// Content font with medium weight
    static var contentMedium: NSFont {
        .systemFont(ofSize: 15, weight: .medium)
    }

    /// Content font with monospaced digits
    static var contentMonospaced: NSFont {
        .monospacedSystemFont(ofSize: content.pointSize, weight: .medium)
    }

    /// Secondary font for metadata and supplementary information
    /// Uses .callout text style
    static var secondary: NSFont {
        .preferredFont(forTextStyle: .callout)
    }

    /// Secondary font with medium weight
    static var secondaryMedium: NSFont {
        .systemFont(ofSize: secondary.pointSize, weight: .medium)
    }

    /// Symbol configuration matching content font size
    static var contentSymbolConfiguration: NSImage.SymbolConfiguration {
        .init(pointSize: 15, weight: .regular)
    }
}
