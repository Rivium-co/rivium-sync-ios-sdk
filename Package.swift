// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "RiviumSync",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "RiviumSync",
            targets: ["RiviumSync"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Rivium-co/pn-protocol-ios.git", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "RiviumSync",
            dependencies: [
                .product(name: "PNProtocol", package: "pn-protocol-ios"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "RiviumSyncTests",
            dependencies: ["RiviumSync"],
            path: "Tests"
        ),
    ]
)
