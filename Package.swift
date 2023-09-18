// swift-tools-version:5.7
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2018-2023 SwiftPrometheus project authors
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
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.1"),

        // ~~~ SwiftPM Plugins ~~~
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "Prometheus",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "CoreMetrics", package: "swift-metrics"),
            ]
        ),
        .testTarget(
            name: "PrometheusTests",
            dependencies: [
                "Prometheus",
            ]
        ),
    ]
)
