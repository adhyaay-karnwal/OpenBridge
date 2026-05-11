//
//  _ContentView.swift
//  ComposerEditorExample
//
//  Created by qaq on 7/1/2026.
//

import Combine
import ComposerEditor
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            StandaloneModeView()
                .tabItem {
                    Label("Standalone", systemImage: "square.dashed")
                }

            CompactModeView()
                .tabItem {
                    Label("Compact", systemImage: "minus.rectangle")
                }

            CommandMenuDemoView()
                .tabItem {
                    Label("Command Menu", systemImage: "command")
                }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview("Full App with Tabs") {
    ContentView()
}
