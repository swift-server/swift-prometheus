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

final class CounterTests: XCTestCase {
    func testCounterWithoutLabels() {
        let client = PrometheusCollectorRegistry()
        let counter = client.makeCounter(name: "foo", labels: [])

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 0

            """
        )

        // Increment by 1
        buffer.removeAll(keepingCapacity: true)
        counter.increment()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 1

            """
        )

        // Increment by 1
        buffer.removeAll(keepingCapacity: true)
        counter.increment()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 2

            """
        )

        // Increment by 2
        buffer.removeAll(keepingCapacity: true)
        counter.increment(by: Int64(2))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 4

            """
        )

        // Increment by 2.5
        buffer.removeAll(keepingCapacity: true)
        counter.increment(by: 2.5)
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 6.5

            """
        )

        // Reset
        buffer.removeAll(keepingCapacity: true)
        counter.reset()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 0

            """
        )
    }

    func testCounterWithLabels() {
        let client = PrometheusCollectorRegistry()
        let counter = client.makeCounter(name: "foo", labels: [("bar", "baz")])

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo{bar="baz"} 0

            """
        )

        // Increment by 1
        buffer.removeAll(keepingCapacity: true)
        counter.increment()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo{bar="baz"} 1

            """
        )

        // Increment by 1
        buffer.removeAll(keepingCapacity: true)
        counter.increment()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo{bar="baz"} 2

            """
        )

        // Increment by 2
        buffer.removeAll(keepingCapacity: true)
        counter.increment(by: Int64(2))
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo{bar="baz"} 4

            """
        )

        // Reset
        buffer.removeAll(keepingCapacity: true)
        counter.reset()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo{bar="baz"} 0

            """
        )
    }
}
