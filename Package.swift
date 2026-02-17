// swift-tools-version:6.0
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2018-2025 SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-prometheus",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9), .tvOS(.v16)],
    products: [
        .library(
            name: "Prometheus",
            targets: ["Prometheus"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "CoreMetrics", package: "swift-metrics"),
            ],
            exclude: [
                "RELEASE.md"
            ]
        ),
        .testTarget(
            name: "PrometheusTests",
            dependencies: [
                "Prometheus"
            ]
        ),
    ]
)

for target in package.targets {
    var settings = target.swiftSettings ?? []

    // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    // Require `any` for existential types.
    settings.append(.enableUpcomingFeature("ExistentialAny"))

    // https://docs.swift.org/compiler/documentation/diagnostics/nonisolated-nonsending-by-default/
    settings.append(.enableUpcomingFeature("NonisolatedNonsendingByDefault"))

    target.swiftSettings = settings
}
