// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnchorPager",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "AnchorPager",
            targets: ["AnchorPager"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/uias/Tabman.git", from: "4.0.1"),
        .package(url: "https://github.com/uias/Pageboy.git", from: "5.0.2")
    ],
    targets: [
        .target(
            name: "AnchorPager",
            dependencies: [
                .product(name: "Tabman", package: "Tabman"),
                .product(name: "Pageboy", package: "Pageboy")
            ],
            path: "Sources/AnchorPager"
        ),
        .testTarget(
            name: "AnchorPagerTests",
            dependencies: ["AnchorPager"],
            path: "Tests/AnchorPagerTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
