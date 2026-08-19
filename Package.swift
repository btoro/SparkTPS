// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SparkTPS",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SparkTPSCore", targets: ["SparkTPSCore"]),
        .executable(name: "SparkTPS", targets: ["SparkTPS"]),
    ],
    targets: [
        .target(name: "SparkTPSCore"),
        .executableTarget(
            name: "SparkTPS",
            dependencies: ["SparkTPSCore"]
        ),
        .testTarget(
            name: "SparkTPSCoreTests",
            dependencies: ["SparkTPSCore"]
        ),
    ]
)
