// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "PayPalMessages",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "PayPalMessages",
            targets: ["PayPalMessages"]
        )
    ],
    targets: [
        .target(
            name: "PayPalMessages",
            path: "Sources/PayPalMessages",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "PayPalMessagesTests",
            dependencies: ["PayPalMessages"],
            path: "Tests/PayPalMessagesTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
