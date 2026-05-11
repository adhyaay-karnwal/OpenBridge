import AppKit

final class AspectFitImageView: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }
}
