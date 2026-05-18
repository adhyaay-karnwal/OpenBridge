//
//  OpenBridgeUnitTests.swift
//  OpenBridgeUnitTests
//
//  Created by qaq on 16/10/2025.
//

@testable import OpenBridge
import Testing

struct OpenBridgeUnitTests {}

struct ChatHeaderIconHoverStyleTests {
    @Test
    func `panel hover affordance uses visible shared dimensions`() {
        #expect(ChatHeaderIconHoverStyle.compactHoverDiameter == 26)
        #expect(ChatHeaderIconHoverStyle.standaloneHoverDiameter == 32)
        #expect(ChatHeaderIconHoverStyle.hoverFillOpacity >= 0.12)
        #expect(ChatHeaderIconHoverStyle.fillOpacity(isHovered: false) == 0)
        #expect(ChatHeaderIconHoverStyle.fillOpacity(isHovered: true) == ChatHeaderIconHoverStyle.hoverFillOpacity)
    }
}
