// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RefereeKit",
    platforms: [.iOS("27.0"), .watchOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "RefereeKit", targets: ["RefereeKit"]),
    ],
    targets: [
        .target(
            name: "RefereeKit",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "RefereeKitTests",
            dependencies: ["RefereeKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
