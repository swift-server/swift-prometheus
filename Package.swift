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
        .package(url: "https://github.com/rauhul/swift-metrics.git", .branch("feature/floating-point-counter")),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: [
                .product(name: "CoreMetrics", package: "swift-metrics"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIO", package: "swift-nio"),
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
