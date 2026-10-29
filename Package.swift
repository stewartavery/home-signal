// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "home-signal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "home-signal", targets: ["home-signal"]),
        .executable(name: "HomeSignalAgent", targets: ["HomeSignalAgent"]),
        .library(name: "HomeSignalCore", targets: ["HomeSignalCore"]),
        .library(name: "HomeSignalKit", targets: ["HomeSignalKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
    ],
    targets: [
        .target(name: "HomeSignalCore"),
        .target(name: "HomeSignalKit", dependencies: ["HomeSignalCore"]),
        .target(name: "HomeSignalLights", dependencies: ["HomeSignalCore"]),
        .target(name: "HomeSignalDisplay", dependencies: ["HomeSignalCore"]),
        .target(name: "HomeSignalMirroring", dependencies: ["HomeSignalCore"]),
        .target(name: "HomeSignalInput", dependencies: ["HomeSignalCore"]),
        .target(name: "HomeSignalCapture", dependencies: ["HomeSignalCore"]),
        .target(
            name: "HomeSignalCLI",
            dependencies: [
                "HomeSignalCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "home-signal", dependencies: ["HomeSignalCLI"]),
        .executableTarget(
            name: "HomeSignalAgent",
            dependencies: [
                "HomeSignalCore",
                "HomeSignalKit",
                "HomeSignalLights",
                "HomeSignalDisplay",
                "HomeSignalMirroring",
                "HomeSignalInput",
                "HomeSignalCapture",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "HomeSignalTests",
            dependencies: [
                "HomeSignalCore",
                "HomeSignalKit",
                "HomeSignalLights",
                "HomeSignalDisplay",
                "HomeSignalMirroring",
                "HomeSignalInput",
                "HomeSignalCapture",
                "HomeSignalCLI",
            ]
        ),
    ]
)
