// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HandScore",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .executable(
            name: "HandScore",
            targets: ["HandScore"]
        )
    ],
    dependencies: [
        .package(path: "./HandScoreCore"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "HandScore",
            dependencies: [
                .product(name: "HandScoreCore", package: "HandScoreCore"),
                "Yams"
            ],
            path: "HAND-Score",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
