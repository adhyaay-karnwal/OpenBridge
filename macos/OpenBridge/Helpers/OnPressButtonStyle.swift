//
//  OnPressButtonStyle.swift
//  OpenBridge
//
//  Created by EYHN on 2025/12/1.
//

import SwiftUI

struct OnPressButtonStyle: ButtonStyle {
    var onPress: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if !oldValue, newValue {
                    onPress()
                }
            }
    }
}
