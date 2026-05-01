// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayMini",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DisplayMini", targets: ["DisplayMini"])],
    targets: [
        .target(name: "DisplayCore"),
        .executableTarget(name: "DisplayMini", dependencies: ["DisplayCore"],
                          linkerSettings: [.linkedFramework("Carbon")]),
        .executableTarget(name: "ControlChecks", dependencies: ["DisplayCore"], path: "Tests/DisplayCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
