//
//  GlassEffectKit.swift
//
//  A standalone Swift Package for cross-platform glass effects
//
//  Usage:
//    import GlassEffectKit
//
//    // Apply glass effect
//    Text("Hello")
//        .safeGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
//
//    // Inject material mode at app root (optional, defaults to .auto)
//    ContentView()
//        .glassMaterialMode(.auto)
//

@_exported import SwiftUI
