import AppKit
import QuartzCore
import SwiftUI

struct BackdropBlurMaskLayer: Equatable {
    let transitionPoint: CGFloat
    let blurRadius: CGFloat
}

struct BackdropBlurMaskStyle: Equatable {
    let heightMultiplier: CGFloat
    let topOffsetMultiplier: CGFloat
    let layers: [BackdropBlurMaskLayer]

    func height(for baseSize: CGFloat) -> CGFloat {
        baseSize * heightMultiplier
    }

    func topOffset(for baseSize: CGFloat) -> CGFloat {
        baseSize * topOffsetMultiplier
    }
}

struct BackdropBlurMaskView: View {
    let baseSize: CGFloat
    let style: BackdropBlurMaskStyle

    private var maskHeight: CGFloat {
        max(0, style.height(for: baseSize))
    }

    var body: some View {
        if maskHeight > 0, !style.layers.isEmpty, BackdropBlurSupport.isAvailable {
            BackdropBlurMaskRepresentable(layers: style.layers)
                .frame(height: maskHeight)
                .offset(y: style.topOffset(for: baseSize))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct BackdropBlurMaskRepresentable: NSViewRepresentable {
    let layers: [BackdropBlurMaskLayer]

    func makeNSView(context _: Context) -> BackdropBlurMaskNSView {
        BackdropBlurMaskNSView(layers: layers)
    }

    func updateNSView(_ nsView: BackdropBlurMaskNSView, context _: Context) {
        nsView.layers = layers
    }
}

private final class BackdropBlurMaskNSView: NSView {
    private struct EffectLayer {
        let spec: BackdropBlurMaskLayer
        let containerLayer: CALayer
        let backdropLayer: CALayer
        let mask: CAGradientLayer
    }

    var layers: [BackdropBlurMaskLayer] {
        didSet {
            guard oldValue != layers else { return }
            rebuildEffectLayers()
        }
    }

    private var effectLayers: [EffectLayer] = []

    override var isFlipped: Bool {
        true
    }

    init(layers: [BackdropBlurMaskLayer]) {
        self.layers = layers
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        rebuildEffectLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for effectLayer in effectLayers {
            effectLayer.containerLayer.frame = bounds
            effectLayer.backdropLayer.frame = bounds
            effectLayer.mask.frame = effectLayer.containerLayer.bounds
            effectLayer.mask.colors = [
                NSColor.black.cgColor,
                NSColor.black.cgColor,
                NSColor.clear.cgColor,
            ]
            effectLayer.mask.locations = [
                NSNumber(value: 0.0),
                NSNumber(value: min(max(effectLayer.spec.transitionPoint, 0), 1)),
                NSNumber(value: 1.0),
            ]
            effectLayer.mask.startPoint = CGPoint(x: 0.5, y: 1)
            effectLayer.mask.endPoint = CGPoint(x: 0.5, y: 0)
        }

        CATransaction.commit()
    }

    private func rebuildEffectLayers() {
        effectLayers.forEach { $0.containerLayer.removeFromSuperlayer() }
        effectLayers = layers.map(Self.makeEffectLayer)

        for effectLayer in effectLayers {
            layer?.addSublayer(effectLayer.containerLayer)
        }

        needsLayout = true
    }

    private static func makeEffectLayer(from spec: BackdropBlurMaskLayer) -> EffectLayer {
        let containerLayer = CALayer()
        containerLayer.backgroundColor = NSColor.clear.cgColor
        containerLayer.masksToBounds = true
        containerLayer.setValue(NSNumber(value: false), forKey: "allowsGroupBlending")

        let backdropLayer = BackdropBlurSupport.makeBackdropLayer(
            blurRadius: spec.blurRadius
        )
        containerLayer.addSublayer(backdropLayer)

        let mask = CAGradientLayer()
        mask.isGeometryFlipped = true
        containerLayer.mask = mask
        return EffectLayer(
            spec: spec,
            containerLayer: containerLayer,
            backdropLayer: backdropLayer,
            mask: mask
        )
    }
}

private enum BackdropBlurSupport {
    private static let backdropLayerClass = NSClassFromString("CABackdropLayer") as? NSObject.Type
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type
    private static let filterSelector = NSSelectorFromString("filterWithType:")

    static var isAvailable: Bool {
        backdropLayerClass != nil && filterClass != nil
    }

    static func makeBackdropLayer(blurRadius: CGFloat) -> CALayer {
        guard
            let backdropLayerClass,
            let backdropLayer = backdropLayerClass.init() as? CALayer
        else {
            return CALayer()
        }

        backdropLayer.name = "backdropBlurMask"
        backdropLayer.backgroundColor = NSColor.clear.cgColor
        backdropLayer.masksToBounds = false
        backdropLayer.filters = makeFilters(blurRadius: blurRadius)
        backdropLayer.setValue(NSNumber(value: 0.125), forKey: "scale")
        backdropLayer.setValue(NSNumber(value: 0), forKey: "bleedAmount")
        backdropLayer.setValue(NSNumber(value: false), forKey: "allowsInPlaceFiltering")
        backdropLayer.setValue(NSNumber(value: false), forKey: "disablesOccludedBackdropBlurs")
        backdropLayer.setValue(NSNumber(value: false), forKey: "ignoresOffscreenGroups")
        backdropLayer.setValue(NSNumber(value: false), forKey: "usesGlobalGroupNamespace")
        backdropLayer.setValue("owningContext", forKey: "groupNamespace")
        return backdropLayer
    }

    private static func makeFilters(blurRadius: CGFloat) -> [Any] {
        var filters: [Any] = []

        if let sdrNormalize = makeFilter(type: "sdrNormalize") {
            filters.append(sdrNormalize)
        }

        if let gaussianBlur = makeFilter(type: "gaussianBlur") {
            gaussianBlur.setValue(NSNumber(value: blurRadius), forKey: "inputRadius")
            gaussianBlur.setValue(NSNumber(value: true), forKey: "inputNormalizeEdges")
            gaussianBlur.setValue("default", forKey: "inputQuality")
            filters.append(gaussianBlur)
        }

        return filters
    }

    private static func makeFilter(type: String) -> NSObject? {
        guard
            let filterClass,
            filterClass.responds(to: filterSelector),
            let unmanaged = filterClass.perform(filterSelector, with: type)
        else {
            return nil
        }

        return unmanaged.takeUnretainedValue() as? NSObject
    }
}
