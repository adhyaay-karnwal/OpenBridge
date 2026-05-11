//
//  GenieEffectAnimator.swift
//  OpenBridge
//
//  Recreates the macOS Genie Effect using SpriteKit mesh warping.
//  Reference: https://harshil.net/blog/recreating-the-mac-genie-effect
//

import AppKit
import SpriteKit

@MainActor
final class GenieEffectAnimator {
    enum Direction {
        case toNotch
        case fromNotch
    }

    struct WindowSnapshot {
        let image: CGImage
        let scale: CGFloat
    }

    private let duration: TimeInterval = 0.5
    private let fps: Double = 60.0
    private let rowCount: Int = 50
    private let slideEndFraction: Double = 0.5
    private let translateStartFraction: Double = 0.4
    private let crossfadeDuration: TimeInterval = 0.12

    private var activeContext: AnimationContext?
    private var completionTimer: DispatchWorkItem?
    private var safetyTimer: DispatchWorkItem?

    private struct AnimationContext {
        let animWindow: NSWindow
        let originalWindow: NSWindow
        let direction: Direction
        let completion: () -> Void
    }

    func animate(
        window: NSWindow,
        direction: Direction,
        snapshot: WindowSnapshot? = nil,
        completion: @escaping () -> Void
    ) {
        finishCurrentAnimation()

        guard let screen = window.screen ?? NSScreen.main else {
            completion()
            return
        }

        let windowFrame = window.frame
        let notchRect = notchTargetRect(for: screen)

        window.displayIfNeeded()
        window.contentView?.displayIfNeeded()

        let resolvedSnapshot = snapshot ?? captureWindowSnapshot(of: window)
        guard let snapshotImage = makeAnimationSnapshot(
            from: resolvedSnapshot,
            windowFrame: windowFrame,
            notchRect: notchRect
        ) else {
            completion()
            return
        }

        let animBounds = windowFrame.union(notchRect)
        let animWindow = makeAnimationWindow(frame: animBounds)

        activeContext = AnimationContext(
            animWindow: animWindow,
            originalWindow: window,
            direction: direction,
            completion: completion
        )

        let viewSize = animBounds.size
        let localWindow = windowFrame.offsetBy(dx: -animBounds.minX, dy: -animBounds.minY)
        let localNotch = notchRect.offsetBy(dx: -animBounds.minX, dy: -animBounds.minY)
        let normWindow = localWindow.unitNormalized(in: viewSize)
        let normNotch = localNotch.unitNormalized(in: viewSize)

        let skView = SKView(frame: CGRect(origin: .zero, size: viewSize))
        skView.allowsTransparency = true
        skView.wantsLayer = true
        skView.layer?.isOpaque = false
        skView.layer?.backgroundColor = .clear
        animWindow.contentView?.addSubview(skView)

        let scene = SKScene(size: viewSize)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill

        let texture = SKTexture(cgImage: snapshotImage)
        texture.filteringMode = .linear

        let imageNode = SKSpriteNode(texture: texture)
        imageNode.size = viewSize
        imageNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageNode.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        scene.addChild(imageNode)

        let (warps, times): ([SKWarpGeometry], [NSNumber])
        switch direction {
        case .toNotch:
            (warps, times) = buildMinimizeWarps(from: normWindow, to: normNotch)
        case .fromNotch:
            (warps, times) = buildRestoreWarps(from: normNotch, to: normWindow)
        }

        guard let first = warps.first,
              let action = SKAction.animate(withWarps: warps, times: times)
        else {
            finishCurrentAnimation()
            return
        }

        imageNode.warpGeometry = first
        skView.presentScene(scene)

        animWindow.orderFrontRegardless()
        if direction == .toNotch {
            // Crossfade: real window (glass) → animation window (snapshot)
            animWindow.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = self.crossfadeDuration
                animWindow.animator().alphaValue = 1
                window.animator().alphaValue = 0
            }
        } else {
            // Keep invisible until SpriteKit has composited the first warp
            // frame (takes ~2 display refreshes after presentScene).
            animWindow.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 / 60.0) {
                animWindow.alphaValue = 1
            }
        }

        imageNode.run(action)

        let work = DispatchWorkItem { [weak self] in
            self?.finishCurrentAnimation()
        }
        completionTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)

        scheduleSafetyTimeout()
    }

    // MARK: - Animation lifecycle

    private func finishCurrentAnimation() {
        guard let ctx = activeContext else { return }
        activeContext = nil

        completionTimer?.cancel()
        completionTimer = nil
        safetyTimer?.cancel()
        safetyTimer = nil

        switch ctx.direction {
        case .toNotch:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ctx.originalWindow.orderOut(nil)
            ctx.originalWindow.alphaValue = 1
            ctx.animWindow.contentView?.subviews.forEach { $0.removeFromSuperview() }
            ctx.animWindow.orderOut(nil)
            CATransaction.commit()
            ctx.completion()

        case .fromNotch:
            // Show real window instantly (behind the animation window)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ctx.originalWindow.alphaValue = 1
            CATransaction.commit()

            // Crossfade: animation window (snapshot) → real window (glass)
            NSAnimationContext.runAnimationGroup { animCtx in
                animCtx.duration = self.crossfadeDuration
                ctx.animWindow.animator().alphaValue = 0
            } completionHandler: {
                MainActor.isolated {
                    ctx.animWindow.contentView?.subviews.forEach { $0.removeFromSuperview() }
                    ctx.animWindow.orderOut(nil)
                    ctx.completion()
                }
            }
        }
    }

    private func scheduleSafetyTimeout() {
        safetyTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finishCurrentAnimation()
        }
        safetyTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0, execute: work)
    }

    // MARK: - Notch target

    private func notchTargetRect(for screen: NSScreen) -> CGRect {
        let notch = screen.notchSize
        let sf = screen.frame
        let w: CGFloat = notch.width > 0 ? notch.width : 150
        let targetHeight: CGFloat = 2
        return CGRect(
            x: sf.minX + (sf.width - w) / 2,
            y: sf.maxY - targetHeight,
            width: w,
            height: targetHeight
        )
    }

    func estimatedNotchContactDelay(for window: NSWindow) -> TimeInterval? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }

        let windowFrame = window.frame
        let notchRect = notchTargetRect(for: screen)
        let verticalDistance = notchRect.minY - windowFrame.minY
        guard verticalDistance > 0 else { return 0 }

        let topEdgeTravel = max(0, notchRect.maxY - windowFrame.maxY)
        let translateProgress = min(1, max(0, topEdgeTravel / verticalDistance))
        let animationProgress = translateStartFraction
            + (1 - translateStartFraction) * translateProgress

        return duration * animationProgress
    }

    // MARK: - Snapshot

    func captureWindowSnapshot(of window: NSWindow) -> WindowSnapshot? {
        guard window.windowNumber > 0, window.frame.width > 0, window.frame.height > 0 else {
            return nil
        }

        let windowID = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        return WindowSnapshot(
            image: image,
            scale: max(1, window.backingScaleFactor)
        )
    }

    private func makeAnimationSnapshot(
        from snapshot: WindowSnapshot?,
        windowFrame: CGRect,
        notchRect: CGRect
    ) -> CGImage? {
        guard let snapshot else { return nil }

        let animBounds = windowFrame.union(notchRect)
        let localWindow = windowFrame.offsetBy(dx: -animBounds.minX, dy: -animBounds.minY)
        let resolvedScale = max(1, snapshot.scale)

        let pixelWidth = max(1, Int(animBounds.width * resolvedScale))
        let pixelHeight = max(1, Int(animBounds.height * resolvedScale))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high

        let pixelRect = CGRect(
            x: localWindow.minX * resolvedScale,
            y: localWindow.minY * resolvedScale,
            width: localWindow.width * resolvedScale,
            height: localWindow.height * resolvedScale
        )
        context.draw(snapshot.image, in: pixelRect)
        return context.makeImage()
    }

    // MARK: - Animation window

    private func makeAnimationWindow(frame: CGRect) -> NSWindow {
        let w = GenieAnimationWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .floating
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.backgroundColor = .clear
        return w
    }

    // MARK: - Warp generation (upward genie: window → notch)

    private func buildMinimizeWarps(
        from initial: CGRect,
        to final: CGRect
    ) -> ([SKWarpGeometry], [NSNumber]) {
        let frameCount = Int(duration * fps)
        guard frameCount > 1 else { return ([], []) }

        let wideMinX = Double(initial.minX)
        let wideMaxX = Double(initial.maxX)
        let leftShift = Double(final.minX) - wideMinX
        let rightShift = Double(final.maxX) - wideMaxX

        let verticalDistance = Double(final.minY - initial.minY)

        let bezierLowY = Double(initial.minY)
        let bezierHighY = Double(final.minY)
        let bezierHeight = bezierHighY - bezierLowY
        let sourcePositions = gridPositions(for: initial)

        var warps: [SKWarpGeometry] = []

        for frame in 0 ..< frameCount {
            let frac = Double(frame) / Double(frameCount - 1)
            let slide = min(1, max(0, frac / slideEndFraction))
            let trans = min(1, max(0,
                                   (frac - translateStartFraction) / (1 - translateStartFraction)))

            let translation = trans * verticalDistance
            let topEdge = min(Double(initial.maxY) + translation, Double(final.maxY))
            let bottomEdge = Double(initial.minY) + translation

            let narrowMinX = wideMinX + slide * leftShift
            let narrowMaxX = wideMaxX + slide * rightShift

            let positions: [SIMD2<Float>] = (0 ... rowCount)
                .flatMap { row -> [SIMD2<Float>] in
                    let t = Double(row) / Double(rowCount)
                    let y = bottomEdge + t * (topEdge - bottomEdge)

                    let xMin = curvedEdgeX(
                        y: y, wideX: wideMinX, narrowX: narrowMinX,
                        lowY: bezierLowY, highY: bezierHighY, height: bezierHeight
                    )
                    let xMax = curvedEdgeX(
                        y: y, wideX: wideMaxX, narrowX: narrowMaxX,
                        lowY: bezierLowY, highY: bezierHighY, height: bezierHeight
                    )
                    return [
                        SIMD2(Float(xMin), Float(y)),
                        SIMD2(Float(xMax), Float(y)),
                    ]
                }

            warps.append(
                SKWarpGeometryGrid(columns: 1, rows: rowCount,
                                   sourcePositions: sourcePositions,
                                   destinationPositions: positions)
            )
        }

        let times = (0 ..< warps.count).map {
            NSNumber(value: Double($0) / fps)
        }

        return (warps, times)
    }

    private func buildRestoreWarps(
        from initial: CGRect,
        to final: CGRect
    ) -> ([SKWarpGeometry], [NSNumber]) {
        let (fwd, _) = buildMinimizeWarps(from: final, to: initial)
        let rev = Array(fwd.reversed())
        let times = (0 ..< rev.count).map {
            NSNumber(value: Double($0) / fps)
        }
        return (rev, times)
    }

    // MARK: - Bezier edge interpolation

    private func curvedEdgeX(
        y: Double,
        wideX: Double,
        narrowX: Double,
        lowY: Double,
        highY: Double,
        height: Double
    ) -> Double {
        guard height > 0 else { return wideX }
        if y <= lowY { return wideX }
        if y >= highY { return narrowX }
        let progress = ((y - lowY) / height).quadraticEaseInOut
        return wideX + progress * (narrowX - wideX)
    }

    private func gridPositions(for rect: CGRect) -> [SIMD2<Float>] {
        (0 ... rowCount)
            .flatMap { row -> [SIMD2<Float>] in
                let t = CGFloat(row) / CGFloat(rowCount)
                let y = rect.minY + t * rect.height
                return [
                    SIMD2(Float(rect.minX), Float(y)),
                    SIMD2(Float(rect.maxX), Float(y)),
                ]
            }
    }
}

// MARK: - Animation Window

/// Prevents macOS from constraining the frame to `screen.visibleFrame`
/// (which excludes the menu bar), allowing the animation to extend
/// all the way to the top edge of the screen behind the menu bar.
private class GenieAnimationWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }
}

// MARK: - Helper Extensions

private extension CGRect {
    func unitNormalized(in size: CGSize) -> CGRect {
        CGRect(
            x: origin.x / size.width,
            y: origin.y / size.height,
            width: width / size.width,
            height: height / size.height
        )
    }
}

private extension Double {
    var quadraticEaseInOut: Double {
        if self < 0.5 {
            2 * self * self
        } else {
            1 - pow(-2 * self + 2, 2) / 2
        }
    }
}
