// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LilaShiftSettingsCore",
    products: [.library(name: "SettingsCore", targets: ["SettingsCore"])],
    targets: [
        .target(name: "SettingsCore"),
        .testTarget(name: "SettingsCoreTests", dependencies: ["SettingsCore"]),
    ]
)
