// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "W9StudioTests", platforms: [.macOS(.v13)], targets: [
    .target(name: "GestaltX"),
    .testTarget(name: "GestaltXTests", dependencies: ["GestaltX"])
])
