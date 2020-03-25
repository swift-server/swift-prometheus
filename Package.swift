// swift-tools-version:4.2

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
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: ["CoreMetrics", "NIOConcurrencyHelpers", "NIO"]),
        .target(
            name: "PrometheusExample",
            dependencies: ["Prometheus", "Metrics"]),
        .testTarget(
            name: "SwiftPrometheusTests",
            dependencies: ["Prometheus"]),
    ]
)
