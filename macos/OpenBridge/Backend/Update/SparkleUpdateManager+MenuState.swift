//
//  SparkleUpdateManager+MenuState.swift
//  OpenBridge
//
//  Manages Sparkle updates with custom UI behavior
//

extension SparkleUpdateManager {
    enum MenuState: Equatable {
        case checkForUpdate
        case downloadingUpdate
        case restartToUpdate
    }

    var isDownloading: Bool {
        menuState == .downloadingUpdate
    }

    var canRelaunch: Bool {
        menuState == .restartToUpdate
    }
}
