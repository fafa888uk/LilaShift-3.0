// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "W7ReportTests", platforms: [.macOS(.v13)], targets: [
    .target(name: "GestaltX"),
    .testTarget(name: "GestaltXTests", dependencies: ["GestaltX"])
])
