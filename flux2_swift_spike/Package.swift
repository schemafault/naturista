// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FluxSpike",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/VincentGourbin/flux-2-swift-mlx", from: "2.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "FluxSpike",
            dependencies: [
                .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
            ]
        ),
    ]
)
