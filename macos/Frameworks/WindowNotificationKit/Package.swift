// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WindowNotificationKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WindowNotificationKit",
            targets: ["WindowNotificationKit"]
        ),
    ],
    targets: [
        .target(
            name: "WindowNotificationKit"
        ),
    ]
)
