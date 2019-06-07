// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "SwiftPrometheus",
    products: [
        .library(
            name: "SwiftPrometheus",
            targets: ["Prometheus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-metrics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: ["NIOConcurrencyHelpers"]),
        .target(
            name: "PrometheusMetrics",
            dependencies: ["Prometheus", "CoreMetrics"]),
        .target(
            name: "PrometheusExample",
            dependencies: ["PrometheusMetrics", "Metrics"]),
        .testTarget(
            name: "SwiftPrometheusTests",
            dependencies: ["Prometheus", "PrometheusMetrics"]),
    ]
)
