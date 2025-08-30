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

    func testGaugeWithSharedMetricNameDistinctLabelSets() {
        let client = PrometheusCollectorRegistry()

        let gauge1 = client.makeGauge(
            name: "foo",
            labels: [("bar", "baz")],
            help: "Shared help text"
        )

        let gauge2 = client.makeGauge(
            name: "foo",
            labels: [("bar", "newBaz"), ("newKey1", "newValue1")],
            help: "Shared help text"
        )

        var buffer = [UInt8]()
        gauge1.set(to: 9.0)
        gauge2.set(to: 4.0)
        gauge1.decrement(by: 12.0)
        gauge2.increment(by: 24.0)
        client.emit(into: &buffer)
        var outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        var actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        var expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo gauge",

            #"foo{bar="baz"} -3.0"#,

            #"foo{bar="newBaz",newKey1="newValue1"} 28.0"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        // Gauges are unregistered in a cascade.

        client.unregisterGauge(gauge1)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo gauge",
            #"foo{bar="newBaz",newKey1="newValue1"} 28.0"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        client.unregisterGauge(gauge2)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([])
        XCTAssertEqual(actualLines, expectedLines)

        let _ = client.makeCounter(
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
            # TYPE foo counter
            foo 0

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

    func testWithMetricNameDescriptorWithFullComponentMatrix() {
        // --- Test Constants ---
        let helpTextValue = "https://help.url/sub"
        let metricNameWithHelp = "metric_with_help"
        let metricNameWithoutHelp = "metric_without_help"
        let incrementValue: Double = 2.0
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
                let expectedMetricLine =
                    "\(nameCase.expectedMetricName)\(labelCase.expectedLabelString) \(incrementValue)"

                var expectedOutput: String
                if let helpText = nameCase.help, !helpText.isEmpty {
                    // If help text exists and is not empty, include the # HELP line.
                    expectedOutput = """
                        # HELP \(nameCase.expectedMetricName) \(helpText)
                        # TYPE \(nameCase.expectedMetricName) gauge
                        \(expectedMetricLine)

                        """
                } else {
                    // Otherwise, use the original format without the # HELP line.
                    expectedOutput = """
                        # TYPE \(nameCase.expectedMetricName) gauge
                        \(expectedMetricLine)

                        """
                }

                allTestCases.append(
                    (
                        descriptor: MetricNameDescriptor(
                            namespace: nameCase.namespace,
                            subsystem: nameCase.subsystem,
                            metricName: nameCase.metricName,
                            unitName: nameCase.unitName,
                            helpText: nameCase.help
                        ),
                        labels: labelCase.labels,
                        expectedOutput: expectedOutput,  // Use the pre-calculated string
                        failureDescription: "\(nameCase.description), \(labelCase.description)"
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
            // --- Test 1: The primary `makeGauge` overload with a `labels` parameter ---
            // This is tested for all cases, including where the labels array is empty.
            let gaugeWithLabels = client.makeGauge(descriptor: testCase.descriptor, labels: testCase.labels)
            gaugeWithLabels.increment(by: incrementValue)

            var buffer = [UInt8]()
            client.emit(into: &buffer)
            let actualOutput = String(decoding: buffer, as: Unicode.UTF8.self)

            var failureMessage = """
                Failed on test case: '\(testCase.failureDescription)'
                Overload: makeGauge(descriptor:labels:)
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
            client.unregisterGauge(gaugeWithLabels)

            // --- Test 2: The convenience `makeGauge` overload without a `labels` parameter ---
            // This should only be tested when the label set is empty.
            if testCase.labels.isEmpty {
                let gaugeWithoutLabels = client.makeGauge(descriptor: testCase.descriptor)
                gaugeWithoutLabels.increment(by: incrementValue)

                var buffer2 = [UInt8]()
                client.emit(into: &buffer2)
                let actualOutput2 = String(decoding: buffer2, as: Unicode.UTF8.self)

                failureMessage = """
                    Failed on test case: '\(testCase.failureDescription)'
                    Overload: makeGauge(descriptor:)
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
                client.unregisterGauge(gaugeWithoutLabels)
            }
        }
    }
}
