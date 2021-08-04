// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "SwiftPrometheus",
    products: [
        .library(
            name: "SwiftPrometheus",
            targets: ["Prometheus"]),
        .executable(
            name: "PrometheusExample",
            targets: ["PrometheusExample"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: [
                .product(name: "CoreMetrics", package: "swift-metrics"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Collections", package: "swift-collections"),
            ]),
        .target(
            name: "PrometheusExample",
            dependencies: [
                .target(name: "Prometheus"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]),
        .testTarget(
            name: "SwiftPrometheusTests",
            dependencies: [.target(name: "Prometheus")]),
    ]
)
