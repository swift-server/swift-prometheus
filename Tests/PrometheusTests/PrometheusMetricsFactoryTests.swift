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

import XCTest
import Prometheus

final class PrometheusMetricsFactoryTests: XCTestCase {
    func testMakeTimers() {
        let client = PrometheusCollectorRegistry()
        let factory = PrometheusMetricsFactory(client: client)

        let timer = factory.makeTimer(label: "foo", dimensions: [("bar", "baz")])
        XCTAssertNotNil(timer as? Histogram<Duration>)
    }

    func testMakeRecorders() {
        let client = PrometheusCollectorRegistry()
        let factory = PrometheusMetricsFactory(client: client)

        let maybeGauge = factory.makeRecorder(label: "foo", dimensions: [("bar", "baz")], aggregate: false)
        XCTAssertNotNil(maybeGauge as? Gauge)

        let maybeRecorder = factory.makeRecorder(label: "bar", dimensions: [], aggregate: true)
        XCTAssertNotNil(maybeRecorder as? Histogram<Double>)
    }

    func testMakeCounters() {
        let client = PrometheusCollectorRegistry()
        let factory = PrometheusMetricsFactory(client: client)

        let maybeCounter = factory.makeCounter(label: "foo", dimensions: [("bar", "baz")])
        XCTAssertNotNil(maybeCounter as? Counter)

        let maybeFloatingPointCounter = factory.makeFloatingPointCounter(label: "foo", dimensions: [("bar", "baz")])
        XCTAssertNotNil(maybeFloatingPointCounter as? Counter)

        XCTAssert(maybeCounter === maybeFloatingPointCounter)

        maybeCounter.increment(by: 1)
        maybeFloatingPointCounter.increment(by: 2.5)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(String(decoding: buffer, as: Unicode.UTF8.self), """
            # TYPE foo counter
            foo{bar="baz"} 3.5

            """
        )

        factory.destroyCounter(maybeCounter)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        XCTAssertEqual(String(decoding: buffer, as: Unicode.UTF8.self), """
            # TYPE foo counter

            """
        )
    }

    func testMakeMeters() {
        let client = PrometheusCollectorRegistry()
        let factory = PrometheusMetricsFactory(client: client)

        let maybeGauge = factory.makeMeter(label: "foo", dimensions: [("bar", "baz")])
        XCTAssertNotNil(maybeGauge as? Gauge)

        maybeGauge.increment(by: 1)
        maybeGauge.decrement(by: 7)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(String(decoding: buffer, as: Unicode.UTF8.self), """
            # TYPE foo gauge
            foo{bar="baz"} -6.0

            """
        )

        // set to double value
        maybeGauge.set(12.45)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        XCTAssertEqual(String(decoding: buffer, as: Unicode.UTF8.self), """
            # TYPE foo gauge
            foo{bar="baz"} 12.45

            """
        )

        // set to int value
        maybeGauge.set(Int64(42)) // needs explicit cast... otherwise ambigious
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        XCTAssertEqual(String(decoding: buffer, as: Unicode.UTF8.self), """
            # TYPE foo gauge
            foo{bar="baz"} 42.0

            """
        )

        factory.destroyMeter(maybeGauge)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        XCTAssertEqual(String(decoding: buffer, as: Unicode.UTF8.self), """
            # TYPE foo gauge

            """
        )
    }

}
