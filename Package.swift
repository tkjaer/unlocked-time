// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "UnlockedTime",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "UnlockedTime", targets: ["UnlockedTime"])
    ],
    targets: [
        .executableTarget(name: "UnlockedTime"),
        .testTarget(name: "UnlockedTimeTests", dependencies: ["UnlockedTime"])
    ]
)