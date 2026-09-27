// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CharonKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CharonKit", targets: ["CharonKit"])
    ],
    targets: [
        .target(
            name: "CharonKit",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(name: "CharonKitTests", dependencies: ["CharonKit"])
    ]
)
