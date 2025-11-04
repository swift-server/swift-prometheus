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

@available(
    *,
    deprecated,
    message: "This test covers deprecated methods. These methods will be refactored in a future version."
)
final class PrometheusCollectorRegistryTests: XCTestCase {
    func testAskingForTheSameCounterReturnsTheSameCounter() {
        let client = PrometheusCollectorRegistry()
        let counter1 = client.makeCounter(name: "foo")
        let counter2 = client.makeCounter(name: "foo")

        XCTAssert(counter1 === counter2)
        counter1.increment()
        counter2.increment(by: Int64(2))

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo 3

            """
        )
    }

    func testAskingForTheSameCounterWithLabelsReturnsTheSameCounter() {
        let client = PrometheusCollectorRegistry()
        let counter1 = client.makeCounter(name: "foo", labels: [("bar", "baz")])
        let counter2 = client.makeCounter(name: "foo", labels: [("bar", "baz")])

        XCTAssert(counter1 === counter2)
        counter1.increment()
        counter2.increment(by: Int64(2))

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo counter
            foo{bar="baz"} 3

            """
        )
    }

    func testAskingForTheSameCounterWithDifferentLabelsReturnsTheDifferentCounters() {
        let client = PrometheusCollectorRegistry()
        let counter1 = client.makeCounter(name: "foo", labels: [("bar", "baz")])
        let counter2 = client.makeCounter(name: "foo", labels: [("bar", "xyz")])

        XCTAssert(counter1 !== counter2)
        counter1.increment()
        counter2.increment(by: Int64(2))

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        let output = String(decoding: buffer, as: Unicode.UTF8.self)
        XCTAssert(output.hasPrefix("# TYPE foo counter\n"))
        XCTAssert(output.contains(#"foo{bar="baz"} 1\#n"#))
        XCTAssert(output.contains(#"foo{bar="xyz"} 2\#n"#))
    }

    func testAskingForTheSameGaugeReturnsTheSameGauge() {
        let client = PrometheusCollectorRegistry()
        let gauge1 = client.makeGauge(name: "foo")
        let gauge2 = client.makeGauge(name: "foo")

        XCTAssert(gauge1 === gauge2)

        gauge1.increment(by: 1)
        gauge2.increment(by: 2)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo 3.0

            """
        )
    }

    func testAskingForTheSameGaugeWithLabelsReturnsTheSameGauge() {
        let client = PrometheusCollectorRegistry()
        let gauge1 = client.makeGauge(name: "foo", labels: [("bar", "baz")])
        let gauge2 = client.makeGauge(name: "foo", labels: [("bar", "baz")])

        XCTAssert(gauge1 === gauge2)

        gauge1.increment(by: 1)
        gauge2.increment(by: 2)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo gauge
            foo{bar="baz"} 3.0

            """
        )
    }

    func testAskingForTheSameTimeHistogramReturnsTheSameTimeHistogram() {
        let client = PrometheusCollectorRegistry()
        let histogram1 = client.makeDurationHistogram(name: "foo", buckets: [.seconds(1), .seconds(2), .seconds(3)])
        let histogram2 = client.makeDurationHistogram(name: "foo", buckets: [.seconds(1), .seconds(2), .seconds(3)])

        XCTAssert(histogram1 === histogram2)
        histogram1.record(.milliseconds(2500))
        histogram2.record(.milliseconds(1500))

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{le="1.0"} 0
            foo_bucket{le="2.0"} 1
            foo_bucket{le="3.0"} 2
            foo_bucket{le="+Inf"} 2
            foo_sum 4.0
            foo_count 2

            """
        )
    }

    func testAskingForTheSameTimeHistogramWithLabelsReturnsTheSameTimeHistogram() {
        let client = PrometheusCollectorRegistry()
        let histogram1 = client.makeDurationHistogram(
            name: "foo",
            labels: [("bar", "baz")],
            buckets: [.seconds(1), .seconds(2), .seconds(3)]
        )
        let histogram2 = client.makeDurationHistogram(
            name: "foo",
            labels: [("bar", "baz")],
            buckets: [.seconds(1), .seconds(2), .seconds(3)]
        )

        XCTAssert(histogram1 === histogram2)
        histogram1.record(.milliseconds(2500))
        histogram2.record(.milliseconds(1500))

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="1.0"} 0
            foo_bucket{bar="baz",le="2.0"} 1
            foo_bucket{bar="baz",le="3.0"} 2
            foo_bucket{bar="baz",le="+Inf"} 2
            foo_sum{bar="baz"} 4.0
            foo_count{bar="baz"} 2

            """
        )
    }

    func testAskingForTheSameValueHistogramReturnsTheSameTimeHistogram() {
        let client = PrometheusCollectorRegistry()
        let histogram1 = client.makeValueHistogram(name: "foo", buckets: [1, 2, 3])
        let histogram2 = client.makeValueHistogram(name: "foo", buckets: [1, 2, 3])

        XCTAssert(histogram1 === histogram2)
        histogram1.record(2.5)
        histogram2.record(1.5)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{le="1.0"} 0
            foo_bucket{le="2.0"} 1
            foo_bucket{le="3.0"} 2
            foo_bucket{le="+Inf"} 2
            foo_sum 4.0
            foo_count 2

            """
        )
    }

    func testAskingForTheSameValueHistogramWithLabelsReturnsTheSameTimeHistogram() {
        let client = PrometheusCollectorRegistry()
        let histogram1 = client.makeValueHistogram(name: "foo", labels: [("bar", "baz")], buckets: [1, 2, 3])
        let histogram2 = client.makeValueHistogram(name: "foo", labels: [("bar", "baz")], buckets: [1, 2, 3])

        XCTAssert(histogram1 === histogram2)
        histogram1.record(2.5)
        histogram2.record(1.5)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="1.0"} 0
            foo_bucket{bar="baz",le="2.0"} 1
            foo_bucket{bar="baz",le="3.0"} 2
            foo_bucket{bar="baz",le="+Inf"} 2
            foo_sum{bar="baz"} 4.0
            foo_count{bar="baz"} 2

            """
        )
    }

    @available(
        *,
        deprecated,
        message: "This test covers deprecated methods. These methods will be refactored in a future version."
    )
    func testUnregisterReregisterWithoutLabels() {
        let registry = PrometheusCollectorRegistry()
        registry.unregisterCounter(registry.makeCounter(name: "name"))
        registry.unregisterGauge(registry.makeGauge(name: "name"))
        registry.unregisterDurationHistogram(registry.makeDurationHistogram(name: "name", buckets: []))
        registry.unregisterValueHistogram(registry.makeValueHistogram(name: "name", buckets: []))
        _ = registry.makeCounter(name: "name")
    }

    func testUnregisterReregisterWithLabels() {
        let registry = PrometheusCollectorRegistry()

        registry.unregisterCounter(registry.makeCounter(name: "name", labels: [("a", "1")]))
        registry.unregisterCounter(registry.makeCounter(name: "name", labels: [("b", "1")]))

        registry.unregisterGauge(registry.makeGauge(name: "name", labels: [("a", "1")]))
        registry.unregisterGauge(registry.makeGauge(name: "name", labels: [("b", "1")]))

        registry.unregisterDurationHistogram(
            registry.makeDurationHistogram(name: "name", labels: [("a", "1")], buckets: [])
        )
        registry.unregisterDurationHistogram(
            registry.makeDurationHistogram(name: "name", labels: [("b", "1")], buckets: [])
        )

        registry.unregisterValueHistogram(registry.makeValueHistogram(name: "name", labels: [("a", "1")], buckets: []))
        registry.unregisterValueHistogram(registry.makeValueHistogram(name: "name", labels: [("b", "1")], buckets: []))

        _ = registry.makeCounter(name: "name", labels: [("a", "1")])
    }

    func testInternalBufferEmitToStringEmitToBuffer() {
        let client = PrometheusCollectorRegistry()

        // Initially, buffer should have no capacity
        XCTAssertEqual(client.internalBufferCapacity(), 0)

        // Create some metrics to establish buffer size.
        let gauge1 = client.makeGauge(name: "test_gauge_1", labels: [])
        let gauge2 = client.makeGauge(name: "test_gauge_2", labels: [("label", "value")])
        let counter = client.makeCounter(name: "test_counter", labels: [])

        gauge1.set(42.0)
        gauge2.set(100.0)
        counter.increment(by: 5.0)

        // First emission - start with emitToBuffer (this will auto-size the internal buffer).
        let output1Buffer = client.emitToBuffer()
        let output1String = client.emitToString()

        XCTAssertFalse(output1String.isEmpty)
        XCTAssertFalse(output1Buffer.isEmpty)

        // Verify both outputs represent the same data.
        XCTAssertEqual(output1String, String(decoding: output1Buffer, as: UTF8.self))

        // Buffer should now have some capacity.
        let initialCapacity = client.internalBufferCapacity()
        XCTAssertGreaterThan(initialCapacity, 0)

        // Second emission - start with emitToString this time.
        let output2String = client.emitToString()
        let output2Buffer = client.emitToBuffer()

        // Same content regardless of method used.
        XCTAssertEqual(output1String, output2String)
        XCTAssertEqual(output1Buffer, output2Buffer)
        XCTAssertEqual(output2String, String(decoding: output2Buffer, as: UTF8.self))
        XCTAssertEqual(client.internalBufferCapacity(), initialCapacity)  // Same capacity

        // Reset the internal buffer.
        client.resetInternalBuffer()
        XCTAssertEqual(client.internalBufferCapacity(), 0)  // Capacity should be reset to 0

        // Add more metrics to change the required buffer size.
        let histogram = client.makeValueHistogram(
            name: "test_histogram",
            labels: [("method", "GET"), ("status", "200")],
            buckets: [0.1, 0.5, 1.0, 5.0, 10.0]
        )
        histogram.record(2.5)

        // This emission should re-calibrate the buffer size - start with emitToString.
        let output3String = client.emitToString()
        let output3Buffer = client.emitToBuffer()

        XCTAssertTrue(output3String.contains("test_histogram"))
        XCTAssertTrue(output3String.contains("test_gauge_1"))
        XCTAssertEqual(output3String, String(decoding: output3Buffer, as: UTF8.self))

        // Buffer should have a new capacity after re-calibration.
        let recalibratedCapacity = client.internalBufferCapacity()
        XCTAssertGreaterThan(recalibratedCapacity, 0)
        XCTAssertGreaterThan(recalibratedCapacity, initialCapacity)

        // Add many more metrics after re-calibration to force buffer resizing.
        // Add multiple gauges with long names and labels to increase buffer requirements.
        var additionalGauges: [Gauge] = []
        for i in 0..<10 {
            let gauge = client.makeGauge(
                name: "test_gauge_with_very_long_name_to_increase_buffer_size_\(i)",
                labels: [
                    ("environment", "production_environment_with_long_value"),
                    ("service", "microservice_with_extremely_long_service_name"),
                    ("region", "us-west-2-availability-zone-1a-with-long-suffix"),
                    ("version", "v1.2.3-build-12345-commit-abcdef123456789"),
                ]
            )
            gauge.set(Double(i * 100))
            additionalGauges.append(gauge)
        }

        // Add multiple counters with extensive labels.
        var additionalCounters: [Counter] = []
        for i in 0..<5 {
            let counter = client.makeCounter(
                name: "http_requests_total_with_very_descriptive_name_\(i)",
                labels: [
                    ("method", "POST"),
                    ("endpoint", "/api/v1/users/profile/settings/notifications/preferences"),
                    ("status_code", "200"),
                    ("user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"),
                    ("client_ip", "192.168.1.100"),
                    ("request_id", "req-\(UUID().uuidString)"),
                ]
            )
            counter.increment(by: Double(i + 1) * 50)
            additionalCounters.append(counter)
        }

        // Add multiple histograms with many buckets.
        var additionalHistograms: [ValueHistogram] = []
        for i in 0..<3 {
            let histogram = client.makeValueHistogram(
                name: "request_duration_seconds_detailed_histogram_\(i)",
                labels: [
                    ("service", "authentication-service-with-long-name"),
                    ("operation", "validate-user-credentials-and-permissions"),
                    ("database", "postgresql-primary-read-write-instance"),
                ],
                buckets: [
                    0.001, 0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0, 15.0, 20.0,
                    30.0,
                ]
            )
            for j in 0..<20 {
                histogram.record(Double(j) * 0.1 + Double(i))
            }
            additionalHistograms.append(histogram)
        }

        // This should definitely trigger buffer resizing due to massive amount of new content.
        let output4String = client.emitToString()
        let output4Buffer = client.emitToBuffer()

        XCTAssertTrue(output4String.contains("test_histogram"))
        XCTAssertTrue(output4String.contains("test_gauge_with_very_long_name"))
        XCTAssertTrue(output4String.contains("http_requests_total_with_very_descriptive_name"))
        XCTAssertTrue(output4String.contains("request_duration_seconds_detailed_histogram"))
        XCTAssertEqual(output4String, String(decoding: output4Buffer, as: UTF8.self))

        // Buffer capacity should have grown significantly to accommodate all the additional metrics.
        let newCapacity = client.internalBufferCapacity()
        XCTAssertGreaterThan(newCapacity, 0)
        XCTAssertGreaterThan(newCapacity, recalibratedCapacity)  // Should be much larger now

        // Subsequent emission should reuse the new buffer size - start with emitToBuffer.
        let output5Buffer = client.emitToBuffer()
        let output5String = client.emitToString()

        XCTAssertEqual(output4String, output5String)
        XCTAssertEqual(output4Buffer, output5Buffer)
        XCTAssertEqual(output5String, String(decoding: output5Buffer, as: UTF8.self))
        XCTAssertEqual(client.internalBufferCapacity(), newCapacity)  // Capacity unchanged

        // Verify buffer reset works with empty registry - unregister all metrics
        client.unregisterGauge(gauge1)
        client.unregisterGauge(gauge2)
        client.unregisterCounter(counter)
        client.unregisterValueHistogram(histogram)

        // Unregister all additional metrics.
        for gauge in additionalGauges {
            client.unregisterGauge(gauge)
        }
        for counter in additionalCounters {
            client.unregisterCounter(counter)
        }
        for histogram in additionalHistograms {
            client.unregisterValueHistogram(histogram)
        }

        client.resetInternalBuffer()
        XCTAssertEqual(client.internalBufferCapacity(), 0)  // Reset to 0 again

        // Test empty output with both methods - start with emitToString.
        let emptyOutputString = client.emitToString()
        let emptyOutputBuffer = client.emitToBuffer()

        XCTAssertTrue(emptyOutputString.isEmpty)
        XCTAssertTrue(emptyOutputBuffer.isEmpty)
        XCTAssertEqual(emptyOutputString, String(decoding: emptyOutputBuffer, as: UTF8.self))

        // With empty output, buffer capacity should remain 0.
        let emptyCapacity = client.internalBufferCapacity()
        XCTAssertEqual(emptyCapacity, 0)
    }

    func testDefaultRegistryDedupTypeHelpPerMetricNameOnEmitWhenMetricNameSharedInMetricFamily() {
        let client = PrometheusCollectorRegistry()

        let gauge1 = client.makeGauge(
            name: "foo",
            labels: [("bar", "baz")],
            help: "Shared help text for all variants"
        )

        let gauge2 = client.makeGauge(
            name: "foo",
            labels: [("bar", "newBaz"), ("newKey1", "newValue1")],
            help: "Shared help text for all variants"
        )

        gauge1.set(to: 9.0)
        gauge2.set(to: 4.0)

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        let outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        let lines = outputString.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // Should have exactly one HELP and one TYPE line.
        let helpLines = lines.filter { $0.hasPrefix("# HELP foo") }
        let typeLines = lines.filter { $0.hasPrefix("# TYPE foo") }
        let metricLines = lines.filter { $0.hasPrefix("foo") && !$0.hasPrefix("# ") }

        XCTAssertEqual(helpLines.count, 1, "Should have exactly one HELP line")
        XCTAssertEqual(typeLines.count, 1, "Should have exactly one TYPE line")
        XCTAssertEqual(metricLines.count, 2, "Should have three metric value lines")

        XCTAssertEqual(helpLines.first, "# HELP foo Shared help text for all variants")
        XCTAssertEqual(typeLines.first, "# TYPE foo gauge")

        // Verify HELP and TYPE appear before any metric values.
        let helpIndex = lines.firstIndex { $0.hasPrefix("# HELP foo") }!
        let typeIndex = lines.firstIndex { $0.hasPrefix("# TYPE foo") }!
        let firstMetricIndex = lines.firstIndex { $0.hasPrefix("foo") && !$0.hasPrefix("# ") }!

        XCTAssertLessThan(helpIndex, firstMetricIndex, "HELP should appear before metric values")
        XCTAssertLessThan(typeIndex, firstMetricIndex, "TYPE should appear before metric values")

        // Verify all three metric values are present (order doesn't matter).
        XCTAssertTrue(metricLines.contains(#"foo{bar="baz"} 9.0"#))
        XCTAssertTrue(metricLines.contains(#"foo{bar="newBaz",newKey1="newValue1"} 4.0"#))
    }

}
