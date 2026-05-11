// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BridgeComputerUse",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CUShared",
            targets: ["CUShared"]
        ),
        .library(
            name: "CUForeground",
            targets: ["CUForeground"]
        ),
        .library(
            name: "CUBackground",
            targets: ["CUBackground"]
        ),
        .executable(
            name: "BridgeComputerUse",
            targets: ["BridgeComputerUse"]
        ),
        .executable(
            name: "BridgeComputerUseDaemon",
            targets: ["BridgeComputerUseDaemon"]
        ),
        .executable(
            name: "BorderSmokeTest",
            targets: ["BorderSmokeTest"]
        ),
        .executable(
            name: "CoordDemo",
            targets: ["CoordDemo"]
        ),
    ],
    dependencies: [
        // Pinned to our fork branch with the FloatingDropPanel sizing fix
        // (https://github.com/jaywcjlove/PermissionFlow/pull/2). Upstream
        // 2.1's NSHostingView defaults cause the drag-helper panel to
        // auto-grow past its measured content size and land off-screen in
        // .accessory hosts; see the PR description for the full trace.
        // Flip back to `exact: "2.1.0"` (or later) once the PR lands.
        //
        // Note on v2.0 status-detection split: that refactor unlinked
        // .bluetooth / .inputMonitoring / .mediaAppleMusic / .screenRecording
        // status detection from the core product. OpenBridge probes TCC
        // directly (AXIsProcessTrusted / CGPreflightScreenCaptureAccess), so
        // we deliberately do not depend on PermissionFlowExtendedStatus.
        .package(
            url: "https://github.com/EYHN/PermissionFlow.git",
            revision: "9b02967a8b47133204c2456c56a1bfb393d4bd95"
        ),
    ],
    targets: [
        .target(
            name: "CUShared",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .target(
            name: "CUForeground",
            dependencies: ["CUShared"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                // Old ComputerUse UX code was written under Swift 5 concurrency;
                // keep this target at v5 so we can port Appearance / coordinator
                // / overlay types without chasing every Swift 6 Sendable
                // warning. CUShared and CUBackground stay on the default.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                // WindowDescriptor.queryWindowCornerRadius needs SkyLight
                // private framework (SLSMainConnectionID etc). Matches the
                // legacy ComputerUse package linker flags.
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "SkyLight",
                ]),
            ]
        ),
        .target(
            name: "CUBackground",
            dependencies: ["CUShared"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(
            name: "BridgeComputerUse",
            dependencies: ["CUShared"]
        ),
        .executableTarget(
            name: "BridgeComputerUseDaemon",
            dependencies: [
                "CUShared",
                "CUBackground",
                "CUForeground",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
            ]
        ),
        .executableTarget(
            name: "BorderSmokeTest",
            dependencies: ["CUShared"]
        ),
        .executableTarget(
            name: "CoordDemo",
            dependencies: ["CUForeground"],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "CUTests",
            dependencies: ["CUShared", "CUBackground"]
        ),
    ]
)
