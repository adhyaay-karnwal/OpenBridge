extension Windows {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
        case topCenter, bottomCenter, leftCenter, rightCenter
        case center, cursor
    }

    func move(_ kind: Kind, offsetX: CGFloat? = nil, offsetY: CGFloat? = nil) {
        let window = windowInstance(for: kind)
        var frame = window.frame
        if let offsetX { frame.origin.x += offsetX }
        if let offsetY { frame.origin.y -= offsetY }
        if let extendablePanel = window as? NSExtendablePanel {
            extendablePanel.setExtendedFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
        }
    }

    func moveTo(_ kind: Kind, position: Position, padding: CGFloat = 16) {
        let window = windowInstance(for: kind)
        let screenFrame = window.screen?.frame ?? .zero
        let windowSize = window.frame.size

        let origin = Self.calculateOrigin(
            position: position,
            screenFrame: screenFrame,
            windowSize: windowSize,
            padding: padding
        )

        if let extendablePanel = window as? NSExtendablePanel {
            var frame = extendablePanel.frame
            frame.origin = origin
            extendablePanel.setExtendedFrame(frame, display: true)
        } else {
            window.setFrameOrigin(origin)
        }
    }

    static func calculateOrigin(
        position: Position,
        screenFrame: CGRect,
        windowSize: CGSize,
        padding: CGFloat
    ) -> CGPoint {
        let left = screenFrame.minX + padding
        let right = screenFrame.maxX - windowSize.width - padding
        let top = screenFrame.maxY - windowSize.height - padding
        let bottom = screenFrame.minY + padding
        let centerX = screenFrame.midX - windowSize.width / 2
        let centerY = screenFrame.midY - windowSize.height / 2

        switch position {
        case .topLeft: return CGPoint(x: left, y: top)
        case .topRight: return CGPoint(x: right, y: top)
        case .bottomLeft: return CGPoint(x: left, y: bottom)
        case .bottomRight: return CGPoint(x: right, y: bottom)
        case .topCenter: return CGPoint(x: centerX, y: top)
        case .bottomCenter: return CGPoint(x: centerX, y: bottom)
        case .leftCenter: return CGPoint(x: left, y: centerY)
        case .rightCenter: return CGPoint(x: right, y: centerY)
        case .center: return CGPoint(x: centerX, y: centerY)
        case .cursor: return CGPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y - windowSize.height)
        }
    }
}
