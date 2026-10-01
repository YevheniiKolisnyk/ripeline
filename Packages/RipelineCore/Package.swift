// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RipelineCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RipelineCore", targets: ["RipelineCore"]),
    ],
    targets: [
        .target(name: "RipelineCore"),
        .testTarget(name: "RipelineCoreTests", dependencies: ["RipelineCore"]),
    ],
    swiftLanguageModes: [.v6]
)
