//
//  KeyboardShortcutDisplay.swift
//  OpenBridge
//
//  Created by qaq on 19/12/2025.
//

struct KeyboardShortcutDisplay {
    let modifiers: [ModifierKey]
    let key: Key

    enum ModifierKey: String {
        case command, shift, option, control
        var symbolName: String {
            rawValue
        }
    }

    enum Key {
        case symbol(String)
        case text(String)

        var isSymbol: Bool {
            if case .symbol = self { return true }
            return false
        }

        var displayValue: String {
            switch self {
            case let .symbol(name): name
            case let .text(value): value
            }
        }
    }
}
