// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlassEffectKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "GlassEffectKit",
            targets: ["GlassEffectKit"]
        ),
    ],
    targets: [
        .target(
            name: "GlassEffectKit"
        ),
    ]
)
