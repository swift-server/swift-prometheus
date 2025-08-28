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

final class HistogramTests: XCTestCase {

    func testFactoryDefaultValueHistogramBuckets() {
        var factory = PrometheusMetricsFactory()
        factory.defaultValueHistogramBuckets = [
            1, 10, 25, 50, 75, 100,
        ]
        let recorder = factory.makeRecorder(label: "label", dimensions: [("a", "b")], aggregate: true)
        recorder.record(Int64(12))

        var buffer = [UInt8]()
        factory.registry.emit(into: &buffer)

        XCTAssertEqual(
            """
            # TYPE label histogram
            label_bucket{a="b",le="1.0"} 0
            label_bucket{a="b",le="10.0"} 0
            label_bucket{a="b",le="25.0"} 1
            label_bucket{a="b",le="50.0"} 1
            label_bucket{a="b",le="75.0"} 1
            label_bucket{a="b",le="100.0"} 1
            label_bucket{a="b",le="+Inf"} 1
            label_sum{a="b"} 12.0
            label_count{a="b"} 1

            """,
            String(decoding: buffer, as: Unicode.UTF8.self)
        )
    }

    func testHistogramWithoutDimensions() {
        let client = PrometheusCollectorRegistry()
        let histogram = client.makeDurationHistogram(
            name: "foo",
            labels: [],
            buckets: [
                .milliseconds(100),
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
            ]
        )

        var buffer = [UInt8]()
        client.emit(into: &buffer)

        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{le="0.1"} 0
            foo_bucket{le="0.25"} 0
            foo_bucket{le="0.5"} 0
            foo_bucket{le="1.0"} 0
            foo_bucket{le="+Inf"} 0
            foo_sum 0.0
            foo_count 0

            """
        )

        // Record 400ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(400_000_000)  // 400ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(
                decoding: buffer,
                as: Unicode.UTF8.self
            ),
            """
            # TYPE foo histogram
            foo_bucket{le="0.1"} 0
            foo_bucket{le="0.25"} 0
            foo_bucket{le="0.5"} 1
            foo_bucket{le="1.0"} 1
            foo_bucket{le="+Inf"} 1
            foo_sum 0.4
            foo_count 1

            """
        )

        // Record 600ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(600_000_000)  // 600ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{le="0.1"} 0
            foo_bucket{le="0.25"} 0
            foo_bucket{le="0.5"} 1
            foo_bucket{le="1.0"} 2
            foo_bucket{le="+Inf"} 2
            foo_sum 1.0
            foo_count 2

            """
        )

        // Record 1200ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(1_200_000_000)  // 1200ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{le="0.1"} 0
            foo_bucket{le="0.25"} 0
            foo_bucket{le="0.5"} 1
            foo_bucket{le="1.0"} 2
            foo_bucket{le="+Inf"} 3
            foo_sum 2.2
            foo_count 3

            """
        )

        // Record 80ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(80_000_000)  // 80ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{le="0.1"} 1
            foo_bucket{le="0.25"} 1
            foo_bucket{le="0.5"} 2
            foo_bucket{le="1.0"} 3
            foo_bucket{le="+Inf"} 4
            foo_sum 2.28
            foo_count 4

            """
        )
    }

    func testHistogramWithOneDimension() {
        let client = PrometheusCollectorRegistry()
        let histogram = client.makeDurationHistogram(
            name: "foo",
            labels: [("bar", "baz")],
            buckets: [
                .milliseconds(100),
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
            ]
        )

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="0.1"} 0
            foo_bucket{bar="baz",le="0.25"} 0
            foo_bucket{bar="baz",le="0.5"} 0
            foo_bucket{bar="baz",le="1.0"} 0
            foo_bucket{bar="baz",le="+Inf"} 0
            foo_sum{bar="baz"} 0.0
            foo_count{bar="baz"} 0

            """
        )

        // Record 400ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(400_000_000)  // 400ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="0.1"} 0
            foo_bucket{bar="baz",le="0.25"} 0
            foo_bucket{bar="baz",le="0.5"} 1
            foo_bucket{bar="baz",le="1.0"} 1
            foo_bucket{bar="baz",le="+Inf"} 1
            foo_sum{bar="baz"} 0.4
            foo_count{bar="baz"} 1

            """
        )

        // Record 600ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(600_000_000)  // 600ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="0.1"} 0
            foo_bucket{bar="baz",le="0.25"} 0
            foo_bucket{bar="baz",le="0.5"} 1
            foo_bucket{bar="baz",le="1.0"} 2
            foo_bucket{bar="baz",le="+Inf"} 2
            foo_sum{bar="baz"} 1.0
            foo_count{bar="baz"} 2

            """
        )

        // Record 1200ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(1_200_000_000)  // 1200ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="0.1"} 0
            foo_bucket{bar="baz",le="0.25"} 0
            foo_bucket{bar="baz",le="0.5"} 1
            foo_bucket{bar="baz",le="1.0"} 2
            foo_bucket{bar="baz",le="+Inf"} 3
            foo_sum{bar="baz"} 2.2
            foo_count{bar="baz"} 3

            """
        )

        // Record 80ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(80_000_000)  // 80ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",le="0.1"} 1
            foo_bucket{bar="baz",le="0.25"} 1
            foo_bucket{bar="baz",le="0.5"} 2
            foo_bucket{bar="baz",le="1.0"} 3
            foo_bucket{bar="baz",le="+Inf"} 4
            foo_sum{bar="baz"} 2.28
            foo_count{bar="baz"} 4

            """
        )
    }

    func testHistogramWithTwoDimension() {
        let client = PrometheusCollectorRegistry()
        let histogram = client.makeDurationHistogram(
            name: "foo",
            labels: [("bar", "baz"), ("abc", "xyz")],
            buckets: [
                .milliseconds(100),
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
            ]
        )

        var buffer = [UInt8]()
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",abc="xyz",le="0.1"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.25"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.5"} 0
            foo_bucket{bar="baz",abc="xyz",le="1.0"} 0
            foo_bucket{bar="baz",abc="xyz",le="+Inf"} 0
            foo_sum{bar="baz",abc="xyz"} 0.0
            foo_count{bar="baz",abc="xyz"} 0

            """
        )

        // Record 400ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(400_000_000)  // 400ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",abc="xyz",le="0.1"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.25"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.5"} 1
            foo_bucket{bar="baz",abc="xyz",le="1.0"} 1
            foo_bucket{bar="baz",abc="xyz",le="+Inf"} 1
            foo_sum{bar="baz",abc="xyz"} 0.4
            foo_count{bar="baz",abc="xyz"} 1

            """
        )

        // Record 600ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(600_000_000)  // 600ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",abc="xyz",le="0.1"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.25"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.5"} 1
            foo_bucket{bar="baz",abc="xyz",le="1.0"} 2
            foo_bucket{bar="baz",abc="xyz",le="+Inf"} 2
            foo_sum{bar="baz",abc="xyz"} 1.0
            foo_count{bar="baz",abc="xyz"} 2

            """
        )

        // Record 1200ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(1_200_000_000)  // 1200ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",abc="xyz",le="0.1"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.25"} 0
            foo_bucket{bar="baz",abc="xyz",le="0.5"} 1
            foo_bucket{bar="baz",abc="xyz",le="1.0"} 2
            foo_bucket{bar="baz",abc="xyz",le="+Inf"} 3
            foo_sum{bar="baz",abc="xyz"} 2.2
            foo_count{bar="baz",abc="xyz"} 3

            """
        )

        // Record 80ms
        buffer.removeAll(keepingCapacity: true)
        histogram.recordNanoseconds(80_000_000)  // 80ms
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # TYPE foo histogram
            foo_bucket{bar="baz",abc="xyz",le="0.1"} 1
            foo_bucket{bar="baz",abc="xyz",le="0.25"} 1
            foo_bucket{bar="baz",abc="xyz",le="0.5"} 2
            foo_bucket{bar="baz",abc="xyz",le="1.0"} 3
            foo_bucket{bar="baz",abc="xyz",le="+Inf"} 4
            foo_sum{bar="baz",abc="xyz"} 2.28
            foo_count{bar="baz",abc="xyz"} 4

            """
        )
    }

    func testDurationHistogramWithSharedMetricNameDistinctLabelSets() {
        let client = PrometheusCollectorRegistry()

        // All histograms with the same name must use the same buckets
        let sharedBuckets: [Duration] = [
            .milliseconds(100),
            .milliseconds(500),
            .seconds(1),
        ]

        let histogram1 = client.makeDurationHistogram(
            name: "foo",
            labels: [("bar", "baz")],
            buckets: sharedBuckets,  // Must match the first registration
            help: "Shared help text"
        )

        let histogram2 = client.makeDurationHistogram(
            name: "foo",
            labels: [("bar", "newBaz"), ("newKey1", "newValue1")],
            buckets: sharedBuckets,  // Must match the first registration
            help: "Shared help text"
        )

        var buffer = [UInt8]()
        histogram1.recordNanoseconds(600_000_000)  // 600ms
        histogram2.recordNanoseconds(150_000_000)  // 150ms
        histogram1.recordNanoseconds(1_500_000_000)  // 1500ms
        histogram2.recordNanoseconds(100_000_000)  // 100ms

        client.emit(into: &buffer)
        var outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        var actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        var expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo histogram",

            #"foo_bucket{bar="baz",le="0.1"} 0"#,
            #"foo_bucket{bar="baz",le="0.5"} 0"#,
            #"foo_bucket{bar="baz",le="1.0"} 1"#,
            #"foo_bucket{bar="baz",le="+Inf"} 2"#,
            #"foo_sum{bar="baz"} 2.1"#,
            #"foo_count{bar="baz"} 2"#,

            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="0.1"} 1"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="0.5"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="1.0"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="+Inf"} 2"#,
            #"foo_sum{bar="newBaz",newKey1="newValue1"} 0.25"#,
            #"foo_count{bar="newBaz",newKey1="newValue1"} 2"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        // Histograms are unregistered in a cascade.

        client.unregisterDurationHistogram(histogram1)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo histogram",
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="0.1"} 1"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="0.5"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="1.0"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="+Inf"} 2"#,
            #"foo_sum{bar="newBaz",newKey1="newValue1"} 0.25"#,
            #"foo_count{bar="newBaz",newKey1="newValue1"} 2"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        client.unregisterDurationHistogram(histogram2)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([])
        XCTAssertEqual(actualLines, expectedLines)

        let _ = client.makeGauge(
            name: "foo",
            labels: [],
            help: "Shared help text"
        )
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # HELP foo Shared help text
            # TYPE foo gauge
            foo 0.0

            """
        )
    }

    func testValueHistogramWithSharedMetricNameDistinctLabelSets() {
        let client = PrometheusCollectorRegistry()

        // All histograms with the same name must use the same buckets
        let sharedBuckets: [Double] = [
            1.0, 5.0, 10.0,
        ]

        let histogram1 = client.makeValueHistogram(
            name: "foo",
            labels: [("bar", "baz")],
            buckets: sharedBuckets,  // Must match the first registration
            help: "Shared help text"
        )

        let histogram2 = client.makeValueHistogram(
            name: "foo",
            labels: [("bar", "newBaz"), ("newKey1", "newValue1")],
            buckets: sharedBuckets,  // Must match the first registration
            help: "Shared help text"
        )

        var buffer = [UInt8]()
        histogram1.record(6.0)
        histogram2.record(2.0)
        histogram1.record(12.0)
        histogram2.record(1.5)

        client.emit(into: &buffer)
        var outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        var actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        var expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo histogram",

            #"foo_bucket{bar="baz",le="1.0"} 0"#,
            #"foo_bucket{bar="baz",le="5.0"} 0"#,
            #"foo_bucket{bar="baz",le="10.0"} 1"#,
            #"foo_bucket{bar="baz",le="+Inf"} 2"#,
            #"foo_sum{bar="baz"} 18.0"#,
            #"foo_count{bar="baz"} 2"#,

            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="1.0"} 0"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="5.0"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="10.0"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="+Inf"} 2"#,
            #"foo_sum{bar="newBaz",newKey1="newValue1"} 3.5"#,
            #"foo_count{bar="newBaz",newKey1="newValue1"} 2"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        // Histograms are unregistered in a cascade.
        client.unregisterValueHistogram(histogram1)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo histogram",
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="1.0"} 0"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="5.0"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="10.0"} 2"#,
            #"foo_bucket{bar="newBaz",newKey1="newValue1",le="+Inf"} 2"#,
            #"foo_sum{bar="newBaz",newKey1="newValue1"} 3.5"#,
            #"foo_count{bar="newBaz",newKey1="newValue1"} 2"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        client.unregisterValueHistogram(histogram2)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([])
        XCTAssertEqual(actualLines, expectedLines)

        let _ = client.makeGauge(
            name: "foo",
            labels: [],
            help: "Shared help text"
        )
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        XCTAssertEqual(
            String(decoding: buffer, as: Unicode.UTF8.self),
            """
            # HELP foo Shared help text
            # TYPE foo gauge
            foo 0.0

            """
        )
    }

    // MARK: - MetricNameDescriptor Histogram Tests

    func testValueHistogramWithMetricNameDescriptorWithFullComponentMatrix() {
        // --- Test Constants ---
        let helpTextValue = "https://help.url/sub"
        let metricNameWithHelp = "metric_with_help"
        let metricNameWithoutHelp = "metric_without_help"
        let observeValue: Double = 0.8
        let buckets: [Double] = [0.5, 1.0, 2.5]
        let client = PrometheusCollectorRegistry()

        // 1. Define the base naming combinations first.
        let baseNameCases:
            [(
                namespace: String?, subsystem: String?, metricName: String, unitName: String?,
                expectedMetricName: String, help: String?, description: String
            )] = [
                // --- Test 1: Cases with help text (using metricNameWithHelp)
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "myapp_subsystem_metric_with_help_total", help: helpTextValue,
                    description: "All components present, with help text"
                ),
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithHelp, unitName: nil,
                    expectedMetricName: "myapp_subsystem_metric_with_help", help: helpTextValue,
                    description: "Unit is nil, with help text"
                ),
                (
                    namespace: "myapp", subsystem: "", metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "myapp_metric_with_help_total", help: helpTextValue,
                    description: "Subsystem is empty string, with help text"
                ),
                (
                    namespace: "myapp", subsystem: nil, metricName: metricNameWithHelp, unitName: nil,
                    expectedMetricName: "myapp_metric_with_help", help: helpTextValue,
                    description: "Subsystem and Unit are nil, with help text"
                ),
                (
                    namespace: "", subsystem: "subsystem", metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "subsystem_metric_with_help_total", help: helpTextValue,
                    description: "Namespace is empty string, with help text"
                ),
                (
                    namespace: nil, subsystem: "subsystem", metricName: metricNameWithHelp, unitName: "",
                    expectedMetricName: "subsystem_metric_with_help", help: helpTextValue,
                    description: "Namespace is nil, Unit is empty string, with help text"
                ),
                (
                    namespace: "", subsystem: nil, metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "metric_with_help_total", help: helpTextValue,
                    description: "Namespace is empty string, Subsystem is nil, with help text"
                ),
                (
                    namespace: nil, subsystem: nil, metricName: metricNameWithHelp, unitName: nil,
                    expectedMetricName: "metric_with_help", help: helpTextValue,
                    description: "Only metric name is present (all nil), with help text"
                ),

                // --- Test 2: Cases without help text (using metricNameWithoutHelp)
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "myapp_subsystem_metric_without_help_total", help: nil,
                    description: "All components present, no help text"
                ),
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: "",
                    expectedMetricName: "myapp_subsystem_metric_without_help", help: nil,
                    description: "Unit is empty string, no help text"
                ),
                (
                    namespace: "myapp", subsystem: nil, metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "myapp_metric_without_help_total", help: nil,
                    description: "Subsystem is nil, no help text"
                ),
                (
                    namespace: "myapp", subsystem: "", metricName: metricNameWithoutHelp, unitName: nil,
                    expectedMetricName: "myapp_metric_without_help", help: nil,
                    description: "Subsystem is empty string, Unit is nil, no help text"
                ),
                (
                    namespace: nil, subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "subsystem_metric_without_help_total", help: nil,
                    description: "Namespace is nil, no help text"
                ),
                (
                    namespace: "", subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: nil,
                    expectedMetricName: "subsystem_metric_without_help", help: nil,
                    description: "Namespace is empty string, Unit is nil, no help text"
                ),
                (
                    namespace: nil, subsystem: "", metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "metric_without_help_total", help: nil,
                    description: "Namespace is nil, Subsystem is empty string, no help text"
                ),
                (
                    namespace: "", subsystem: "", metricName: metricNameWithoutHelp, unitName: "",
                    expectedMetricName: "metric_without_help", help: nil,
                    description: "Only metric name is present (all empty strings), no help text"
                ),
            ]

        // 2. Define the label combinations to test.
        let labelCases: [(labels: [(String, String)], expectedLabelString: String, description: String)] = [
            (labels: [("method", "get")], expectedLabelString: "{method=\"get\"}", description: "with one label"),
            (
                labels: [("status", "200"), ("path", "/api/v1")],
                expectedLabelString: "{status=\"200\",path=\"/api/v1\"}", description: "with two labels"
            ),
        ]

        // 3. Programmatically generate the final, full matrix by crossing name cases with label cases.
        var allTestCases:
            [(
                descriptor: MetricNameDescriptor, labels: [(String, String)], expectedOutput: String,
                failureDescription: String
            )] = []

        for nameCase in baseNameCases {
            for labelCase in labelCases {
                let descriptor = MetricNameDescriptor(
                    namespace: nameCase.namespace,
                    subsystem: nameCase.subsystem,
                    metricName: nameCase.metricName,
                    unitName: nameCase.unitName,
                    helpText: nameCase.help
                )

                let expectedOutput = self.generateHistogramOutput(
                    metricName: nameCase.expectedMetricName,
                    labelString: labelCase.expectedLabelString,
                    buckets: buckets,
                    observedValue: observeValue,
                    helpText: nameCase.help ?? ""
                )

                let failureDescription = "ValueHistogram: \(nameCase.description), \(labelCase.description)"

                allTestCases.append(
                    (
                        descriptor: descriptor,
                        labels: labelCase.labels,
                        expectedOutput: expectedOutput,
                        failureDescription: failureDescription
                    )
                )
            }
        }

        let expectedTestCaseCount = baseNameCases.count * labelCases.count
        XCTAssertEqual(
            allTestCases.count,
            expectedTestCaseCount,
            "Test setup failed: Did not generate the correct number of test cases."
        )

        // 4. Loop through the complete, generated test matrix.
        for testCase in allTestCases {
            // --- Test 1: The `makeValueHistogram` overload with a `labels` parameter ---
            let histogramWithLabels = client.makeValueHistogram(
                descriptor: testCase.descriptor,
                labels: testCase.labels,
                buckets: buckets
            )
            histogramWithLabels.record(observeValue)

            var buffer = [UInt8]()
            client.emit(into: &buffer)
            let actualOutput = String(decoding: buffer, as: Unicode.UTF8.self)

            var failureMessage = """
                Failed on test case: '\(testCase.failureDescription)'
                Overload: makeValueHistogram(descriptor:labels:buckets:)
                - Descriptor: \(testCase.descriptor)
                - Labels: \(testCase.labels)
                - Expected Output:
                ---
                \(testCase.expectedOutput)
                ---
                - Actual Output:
                ---
                \(actualOutput)
                ---
                """
            XCTAssertEqual(actualOutput, testCase.expectedOutput, failureMessage)
            client.unregisterValueHistogram(histogramWithLabels)

            // --- Test 2: The `makeValueHistogram` overload without a `labels` parameter ---
            if testCase.labels.isEmpty {
                let histogramWithoutLabels = client.makeValueHistogram(
                    descriptor: testCase.descriptor,
                    buckets: buckets
                )
                histogramWithoutLabels.record(observeValue)

                var buffer2 = [UInt8]()
                client.emit(into: &buffer2)
                let actualOutput2 = String(decoding: buffer2, as: Unicode.UTF8.self)

                failureMessage = """
                    Failed on test case: '\(testCase.failureDescription)'
                    Overload: makeValueHistogram(descriptor:buckets:)
                    - Descriptor: \(testCase.descriptor)
                    - Expected Output:
                    ---
                    \(testCase.expectedOutput)
                    ---
                    - Actual Output:
                    ---
                    \(actualOutput2)
                    ---
                    """
                XCTAssertEqual(actualOutput2, testCase.expectedOutput, failureMessage)
                client.unregisterValueHistogram(histogramWithoutLabels)
            }
        }
    }

    func testDurationHistogramWithMetricNameDescriptorWithFullComponentMatrix() {
        // --- Test Constants ---
        let helpTextValue = "https://help.url/sub"
        let metricNameWithHelp = "metric_with_help"
        let metricNameWithoutHelp = "metric_without_help"
        let observeValue = Duration.milliseconds(400)
        let buckets: [Duration] = [
            .milliseconds(100),
            .milliseconds(250),
            .milliseconds(500),
            .seconds(1),
        ]
        let client = PrometheusCollectorRegistry()

        // 1. Define the base naming combinations first.
        let baseNameCases:
            [(
                namespace: String?, subsystem: String?, metricName: String, unitName: String?,
                expectedMetricName: String, help: String?, description: String
            )] = [
                // --- Test 1: Cases with help text (using metricNameWithHelp)
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "myapp_subsystem_metric_with_help_total", help: helpTextValue,
                    description: "All components present, with help text"
                ),
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithHelp, unitName: nil,
                    expectedMetricName: "myapp_subsystem_metric_with_help", help: helpTextValue,
                    description: "Unit is nil, with help text"
                ),
                (
                    namespace: "myapp", subsystem: "", metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "myapp_metric_with_help_total", help: helpTextValue,
                    description: "Subsystem is empty string, with help text"
                ),
                (
                    namespace: "myapp", subsystem: nil, metricName: metricNameWithHelp, unitName: nil,
                    expectedMetricName: "myapp_metric_with_help", help: helpTextValue,
                    description: "Subsystem and Unit are nil, with help text"
                ),
                (
                    namespace: "", subsystem: "subsystem", metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "subsystem_metric_with_help_total", help: helpTextValue,
                    description: "Namespace is empty string, with help text"
                ),
                (
                    namespace: nil, subsystem: "subsystem", metricName: metricNameWithHelp, unitName: "",
                    expectedMetricName: "subsystem_metric_with_help", help: helpTextValue,
                    description: "Namespace is nil, Unit is empty string, with help text"
                ),
                (
                    namespace: "", subsystem: nil, metricName: metricNameWithHelp, unitName: "total",
                    expectedMetricName: "metric_with_help_total", help: helpTextValue,
                    description: "Namespace is empty string, Subsystem is nil, with help text"
                ),
                (
                    namespace: nil, subsystem: nil, metricName: metricNameWithHelp, unitName: nil,
                    expectedMetricName: "metric_with_help", help: helpTextValue,
                    description: "Only metric name is present (all nil), with help text"
                ),

                // --- Test 2: Cases without help text (using metricNameWithoutHelp)
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "myapp_subsystem_metric_without_help_total", help: nil,
                    description: "All components present, no help text"
                ),
                (
                    namespace: "myapp", subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: "",
                    expectedMetricName: "myapp_subsystem_metric_without_help", help: nil,
                    description: "Unit is empty string, no help text"
                ),
                (
                    namespace: "myapp", subsystem: nil, metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "myapp_metric_without_help_total", help: nil,
                    description: "Subsystem is nil, no help text"
                ),
                (
                    namespace: "myapp", subsystem: "", metricName: metricNameWithoutHelp, unitName: nil,
                    expectedMetricName: "myapp_metric_without_help", help: nil,
                    description: "Subsystem is empty string, Unit is nil, no help text"
                ),
                (
                    namespace: nil, subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "subsystem_metric_without_help_total", help: nil,
                    description: "Namespace is nil, no help text"
                ),
                (
                    namespace: "", subsystem: "subsystem", metricName: metricNameWithoutHelp, unitName: nil,
                    expectedMetricName: "subsystem_metric_without_help", help: nil,
                    description: "Namespace is empty string, Unit is nil, no help text"
                ),
                (
                    namespace: nil, subsystem: "", metricName: metricNameWithoutHelp, unitName: "total",
                    expectedMetricName: "metric_without_help_total", help: nil,
                    description: "Namespace is nil, Subsystem is empty string, no help text"
                ),
                (
                    namespace: "", subsystem: "", metricName: metricNameWithoutHelp, unitName: "",
                    expectedMetricName: "metric_without_help", help: nil,
                    description: "Only metric name is present (all empty strings), no help text"
                ),
            ]

        // 2. Define the label combinations to test.
        let labelCases: [(labels: [(String, String)], expectedLabelString: String, description: String)] = [
            (labels: [("method", "get")], expectedLabelString: "{method=\"get\"}", description: "with one label"),
            (
                labels: [("status", "200"), ("path", "/api/v1")],
                expectedLabelString: "{status=\"200\",path=\"/api/v1\"}", description: "with two labels"
            ),
        ]

        // 3. Programmatically generate the final, full matrix by crossing name cases with label cases.
        var allTestCases:
            [(
                descriptor: MetricNameDescriptor, labels: [(String, String)], expectedOutput: String,
                failureDescription: String
            )] = []

        for nameCase in baseNameCases {
            for labelCase in labelCases {
                let descriptor = MetricNameDescriptor(
                    namespace: nameCase.namespace,
                    subsystem: nameCase.subsystem,
                    metricName: nameCase.metricName,
                    unitName: nameCase.unitName,
                    helpText: nameCase.help
                )

                // Convert Durations to Doubles (seconds) for expected output generation
                let bucketsInSeconds = buckets.map {
                    Double($0.components.seconds) + Double($0.components.attoseconds) / 1_000_000_000_000_000_000.0
                }
                let observedValueInSeconds =
                    Double(observeValue.components.seconds) + Double(observeValue.components.attoseconds)
                    / 1_000_000_000_000_000_000.0

                let expectedOutput = self.generateHistogramOutput(
                    metricName: nameCase.expectedMetricName,
                    labelString: labelCase.expectedLabelString,
                    buckets: bucketsInSeconds,
                    observedValue: observedValueInSeconds,
                    helpText: nameCase.help ?? ""
                )

                let failureDescription = "DurationHistogram: \(nameCase.description), \(labelCase.description)"

                allTestCases.append(
                    (
                        descriptor: descriptor,
                        labels: labelCase.labels,
                        expectedOutput: expectedOutput,
                        failureDescription: failureDescription
                    )
                )
            }
        }

        let expectedTestCaseCount = baseNameCases.count * labelCases.count
        XCTAssertEqual(
            allTestCases.count,
            expectedTestCaseCount,
            "Test setup failed: Did not generate the correct number of test cases."
        )

        // 4. Loop through the complete, generated test matrix.
        for testCase in allTestCases {
            // --- Test 1: The `makeDurationHistogram` overload with a `labels` parameter ---
            let histogramWithLabels = client.makeDurationHistogram(
                descriptor: testCase.descriptor,
                labels: testCase.labels,
                buckets: buckets
            )
            histogramWithLabels.record(observeValue)

            var buffer = [UInt8]()
            client.emit(into: &buffer)
            let actualOutput = String(decoding: buffer, as: Unicode.UTF8.self)

            var failureMessage = """
                Failed on test case: '\(testCase.failureDescription)'
                Overload: makeDurationHistogram(descriptor:labels:buckets:)
                - Descriptor: \(testCase.descriptor)
                - Labels: \(testCase.labels)
                - Expected Output:
                ---
                \(testCase.expectedOutput)
                ---
                - Actual Output:
                ---
                \(actualOutput)
                ---
                """
            XCTAssertEqual(actualOutput, testCase.expectedOutput, failureMessage)
            client.unregisterDurationHistogram(histogramWithLabels)

            // --- Test 2: The `makeDurationHistogram` overload without a `labels` parameter ---
            if testCase.labels.isEmpty {
                let histogramWithoutLabels = client.makeDurationHistogram(
                    descriptor: testCase.descriptor,
                    buckets: buckets
                )
                histogramWithoutLabels.record(observeValue)

                var buffer2 = [UInt8]()
                client.emit(into: &buffer2)
                let actualOutput2 = String(decoding: buffer2, as: Unicode.UTF8.self)

                failureMessage = """
                    Failed on test case: '\(testCase.failureDescription)'
                    Overload: makeDurationHistogram(descriptor:buckets:)
                    - Descriptor: \(testCase.descriptor)
                    - Expected Output:
                    ---
                    \(testCase.expectedOutput)
                    ---
                    - Actual Output:
                    ---
                    \(actualOutput2)
                    ---
                    """
                XCTAssertEqual(actualOutput2, testCase.expectedOutput, failureMessage)
                client.unregisterDurationHistogram(histogramWithoutLabels)
            }
        }
    }

    // MARK: - Helpers

    /// Generates the expected Prometheus exposition format string for a histogram with a single observation.
    private func generateHistogramOutput(
        metricName: String,
        labelString: String,
        buckets: [Double],
        observedValue: Double,
        helpText: String = ""
    ) -> String {

        var output: String = ""
        if !helpText.isEmpty {
            // If help text is not empty, include the # HELP line.
            output += "# HELP \(metricName) \(helpText)\n"
        }
        output += "# TYPE \(metricName) histogram\n"
        let labelsWithLe = { (le: String) -> String in
            guard labelString.isEmpty else {
                // Insert 'le' at the end of the existing labels
                return "{\(labelString.dropFirst().dropLast()),le=\"\(le)\"}"
            }
            return "{le=\"\(le)\"}"
        }

        var cumulativeCount = 0
        for bucket in buckets {
            if observedValue <= bucket {
                cumulativeCount = 1
            }
            output += "\(metricName)_bucket\(labelsWithLe("\(bucket)")) \(cumulativeCount)\n"
        }

        let totalObservations = 1
        output += "\(metricName)_bucket\(labelsWithLe("+Inf")) \(totalObservations)\n"
        output += "\(metricName)_sum\(labelString) \(observedValue)\n"

        output += "\(metricName)_count\(labelString) \(totalObservations)\n"

        return output
    }
}
