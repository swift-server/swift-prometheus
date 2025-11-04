//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2024 SwiftPrometheus project authors
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

@available(
    *,
    deprecated,
    message: "This test covers deprecated methods. These methods will be refactored in a future version."
)
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

    func testIllegalHelpText() async throws {
        let registry = PrometheusCollectorRegistry()

        registry.makeCounter(
            name: "metric",
            labels: [("key", "value")],
            help:
                "\u{007F}T\0his# is\u{200B} an_ \u{001B}ex\u{00AD}ample\u{001B} \u{202A}(help-\r\nt\u{2028}ext),\u{2029} \u{2066}link: https://help.url/sub"
        ).increment()

        var buffer = [UInt8]()
        registry.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self).split(separator: "\n").sorted().joined(separator: "\n"),
            """
            # HELP metric This# is an_ example (help-text), link: https://help.url/sub
            # TYPE metric counter
            metric{key="value"} 1
            """
        )
    }
}
