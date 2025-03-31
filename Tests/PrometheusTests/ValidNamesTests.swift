//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2024 the SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Prometheus
import XCTest

final class ValidNamesTests: XCTestCase {
    func testCounterWithEmoji() {
        let client = PrometheusCollectorRegistry()
        let counter = client.makeCounter(name: "coffee☕️", labels: [])
        counter.increment()

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE coffee_ counter
            coffee_ 1

            """
        )
    }

    func testIllegalMetricNames() async throws {
        let registry = PrometheusCollectorRegistry()

        /// Notably, newlines must not allow creating whole new metric root
        let tests = [
            "name",
            """
            name{bad="haha"} 121212121
            bad_bad 12321323
            """,
        ]

        for test in tests {
            registry.makeCounter(
                name: test,
                labels: []
            ).increment()
        }

        var buffer = [UInt8]()
        registry.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self).split(separator: "\n").sorted().joined(separator: "\n"),
            """
            # TYPE name counter
            # TYPE name_bad__haha___121212121_bad_bad_12321323 counter
            name 1
            name_bad__haha___121212121_bad_bad_12321323 1
            """
        )
    }

    func testIllegalLabelNames() async throws {
        let registry = PrometheusCollectorRegistry()

        let tests = [
            """
            name{bad="haha"} 121212121
            bad_bad 12321323
            """
        ]

        for test in tests {
            registry.makeCounter(
                name: "metric",
                labels: [(test, "value")]
            ).increment()
        }

        var buffer = [UInt8]()
        registry.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self).split(separator: "\n").sorted().joined(separator: "\n"),
            """
            # TYPE metric counter
            metric{name_bad__haha___121212121_bad_bad_12321323="value"} 1
            """
        )
    }
}
