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
        .package(url: "https://github.com/tomerd/swift-server-metrics-api-proposal.git", .branch("master"))
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: ["Metrics"]),
        .target(
            name: "PrometheusExample",
            dependencies: ["Prometheus"]),
        .testTarget(
            name: "SwiftPrometheusTests",
            dependencies: ["Prometheus"]),
    ]
)
