// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "SwiftPrometheus",
    products: [
        .library(
            name: "SwiftPrometheus",
            targets: ["Prometheus"]),
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: []),
        .target(
            name: "PrometheusExample",
            dependencies: ["Prometheus"]),
        .testTarget(
            name: "SwiftPrometheusTests",
            dependencies: ["Prometheus"]),
    ]
)
