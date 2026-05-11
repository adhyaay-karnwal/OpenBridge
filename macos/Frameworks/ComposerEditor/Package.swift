// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ComposerEditor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ComposerEditor",
            targets: ["ComposerEditor"]
        ),
    ],
    dependencies: [
        .package(path: "../GlassEffectKit"),
    ],
    targets: [
        .target(
            name: "ComposerEditor",
            dependencies: ["GlassEffectKit"]
        ),
        .testTarget(
            name: "ComposerEditorTests",
            dependencies: ["ComposerEditor"]
        ),
    ]
)
