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

import Prometheus
import XCTest

final class GaugeTests: XCTestCase {
    func testGaugeWithoutLabels() {
        let client = PrometheusCollectorRegistry()
        let gauge = client.makeGauge(name: "foo", labels: [])

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo 0.0

            """
        )

        // Set to 1
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(1))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo 1.0

            """
        )

        // Set to 2
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(2))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo 2.0

            """
        )

        // Set to 4
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(4))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo 4.0

            """
        )

        // Reset
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(0))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo 0.0

            """
        )
    }

    func testGaugeWithLabels() {
        let client = PrometheusCollectorRegistry()
        let gauge = client.makeGauge(name: "foo", labels: [("bar", "baz")])

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo{bar="baz"} 0.0

            """
        )

        // Set to 1
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(1))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo{bar="baz"} 1.0

            """
        )

        // Set to 2
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(2))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo{bar="baz"} 2.0

            """
        )

        // Set to 4
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(4))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo{bar="baz"} 4.0

            """
        )

        // Reset
        buffer.removeAll(keepingCapacity: true)
        gauge.record(Int64(0))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo{bar="baz"} 0.0

            """
        )
    }

    func testGaugeSetToFromMultipleTasks() async {
        let client = PrometheusCollectorRegistry()
        let gauge = client.makeGauge(name: "foo", labels: [("bar", "baz")])
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100_000 {
                group.addTask {
                    gauge.set(to: Double.random(in: 0..<20))
                }
            }
        }
    }

    func testIncByFromMultipleTasks() async {
        let client = PrometheusCollectorRegistry()
        let gauge = client.makeGauge(name: "foo", labels: [("bar", "baz")])
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100_000 {
                group.addTask {
                    gauge.increment(by: Double.random(in: 0..<1))
                }
            }
        }
    }
}
