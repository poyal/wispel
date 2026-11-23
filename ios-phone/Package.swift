// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "WispelCore", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "WispelCore", targets: ["WispelCore"])], targets: [.target(name: "WispelCore", path: "Core"), .testTarget(name: "CoreTests", dependencies: ["WispelCore"], path: "Tests")])
