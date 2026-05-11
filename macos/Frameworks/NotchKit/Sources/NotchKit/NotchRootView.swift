import SwiftUI

@MainActor
struct NotchRootView: View {
    @State private var model: NotchRuntimeModel

    init(model: NotchRuntimeModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NotchKitView(
            model: model.packageModel,
            onCompactLeadingSizeChange: model.updateCompactLeadingSize,
            onCompactTrailingSizeChange: model.updateCompactTrailingSize,
            onExpandedLeadingSizeChange: model.updateExpandedLeadingSize,
            onExpandedTrailingSizeChange: model.updateExpandedTrailingSize,
            onExpandedContentSizeChange: model.updateExpandedContentSize
        ) {
            model.scene.compactLeadingSlot
        } compactTrailing: {
            model.scene.compactTrailingSlot
        } expandedLeading: {
            model.scene.expandedLeadingSlot
        } expandedTrailing: {
            model.scene.expandedTrailingSlot
        } expandedContent: {
            model.scene.expandedContent
        }
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
