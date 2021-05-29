// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package: Package = Package(
    name: "CornucopiaUDS",
    defaultLocalization: "en",
    platforms: [
        .iOS("13.4"),
        .macOS("10.15.4"),
        .tvOS("13.4")
    ],
    products: [
        .library(name: "CornucopiaUDS", targets: ["CornucopiaUDS"]),
        .executable(name: "uds", targets: ["Example"]),
    ],
    dependencies: [
        // CornucopiaUDS
        .package(url: "https://github.com/Cornucopia-Swift/CornucopiaCore", .branch("master")),
        // ExampleUDS
        .package(url: "https://github.com/Cornucopia-Swift/CornucopiaStreams", .branch("master")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "0.4.3")),
    ],
    targets: [
        .target(name: "CornucopiaUDS", dependencies: ["CornucopiaCore"]),
        .target(name: "Example", dependencies: [
            "CornucopiaUDS",
            "CornucopiaStreams",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .testTarget(
            name: "CornucopiaUDSTests",
            dependencies: ["CornucopiaUDS"]),
    ]
)
