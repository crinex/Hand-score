// swift-tools-version:6.0
//
// HandScoreCore — ANE inference runtime used by the HAND-Score iOS benchmark app.
//
// Originally derived from AnemllCore
// (https://github.com/Anemll/Anemll, MIT License). Renamed and packaged
// independently for the HAND-Score release. The original copyright notice
// is preserved verbatim in LICENSE-AnemllCore at this package root.
//
import PackageDescription

let package = Package(
    name: "HandScoreCore",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "HandScoreCore",
            targets: ["HandScoreCore"]
        )
    ],
    dependencies: [
        // YAML config parser (meta.yaml shipped with every ANE-converted model)
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // Jinja-compatible templating for chat templates
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.14.0"),
        // HuggingFace tokenizer runtime. Pinned to the exact revision validated
        // against the HAND-Score paper measurements (the app Package.resolved
        // as of 2026-05-07). swift-transformers tracks `main` upstream, so an
        // unpinned dependency would be a moving target for reproducibility.
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            revision: "7f1f9d06c8fc789936a4cca2affe96528e99f47d"
        )
    ],
    targets: [
        .target(
            name: "HandScoreCore",
            dependencies: [
                "Yams",
                "Stencil",
                .product(name: "Transformers", package: "swift-transformers")
            ]
        )
    ]
)
