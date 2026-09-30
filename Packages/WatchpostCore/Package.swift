// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WatchpostCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WatchpostCore", targets: ["WatchpostCore"])
    ],
    targets: [
        .target(name: "WatchpostCore"),
        .testTarget(name: "WatchpostCoreTests", dependencies: ["WatchpostCore"])
    ]
)
