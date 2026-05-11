//
//  _MessageListView.swift
//  ComposerEditorExample
//
//  Created by qaq on 7/1/2026.
//

import SwiftUI

struct MessageListView: View {
    let messages: [String]
    let backgroundColor: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                        .padding(10)
                        .background(backgroundColor)
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }
}
