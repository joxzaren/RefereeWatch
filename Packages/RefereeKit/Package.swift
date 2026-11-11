// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RefereeKit",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS("26.0")],
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
