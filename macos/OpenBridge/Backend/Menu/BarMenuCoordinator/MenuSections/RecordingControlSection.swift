import AppKit

private let durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .short
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    return formatter
}()

@MainActor
final class RecordingControlSection: BarMenuCoordinator.SectionBuilder {
    func sectionItems() -> [NSMenuItem] {
        []
    }
}
