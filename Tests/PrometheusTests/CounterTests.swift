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

    func testCounterWithSharedMetricNamDistinctLabelSets() {
        let client = PrometheusCollectorRegistry()

        let counter1 = client.makeCounter(
            name: "foo",
            labels: [("bar", "baz")],
            help: "Shared help text"
        )

        let counter2 = client.makeCounter(
            name: "foo",
            labels: [("bar", "newBaz"), ("newKey1", "newValue1")],
            help: "Shared help text"
        )

        var buffer = [UInt8]()
        counter1.increment(by: Int64(9))
        counter2.increment(by: Int64(4))
        counter1.increment(by: Int64(3))
        counter2.increment(by: Int64(20))
        client.emit(into: &buffer)
        var outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        var actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        var expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo counter",

            #"foo{bar="baz"} 12"#,

            #"foo{bar="newBaz",newKey1="newValue1"} 24"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        // Counters are unregistered in a cascade.

        client.unregisterCounter(counter1)
        buffer.removeAll(keepingCapacity: true)
        client.emit(into: &buffer)
        outputString = String(decoding: buffer, as: Unicode.UTF8.self)
        actualLines = Set(outputString.components(separatedBy: .newlines).filter { !$0.isEmpty })
        expectedLines = Set([
            "# HELP foo Shared help text",
            "# TYPE foo counter",
            #"foo{bar="newBaz",newKey1="newValue1"} 24"#,
        ])
        XCTAssertEqual(actualLines, expectedLines)

        client.unregisterCounter(counter2)
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

    func testWithMetricNameDescriptorWithFullComponentMatrix() {
        // --- Test Constants ---
        let helpTextValue = "https://help.url/sub"
        let metricNameWithHelp = "metric_with_help"
        let metricNameWithoutHelp = "metric_without_help"
        let incrementValue: Int64 = 2
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
                        # TYPE \(nameCase.expectedMetricName) counter
                        \(expectedMetricLine)

                        """
                } else {
                    // Otherwise, use the original format without the # HELP line.
                    expectedOutput = """
                        # TYPE \(nameCase.expectedMetricName) counter
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
            // --- Test 1: The primary `makeCounter` overload with a `labels` parameter ---
            // This is tested for all cases, including where the labels array is empty.
            let counterWithLabels = client.makeCounter(descriptor: testCase.descriptor, labels: testCase.labels)
            counterWithLabels.increment(by: incrementValue)

            var buffer = [UInt8]()
            client.emit(into: &buffer)
            let actualOutput = String(decoding: buffer, as: Unicode.UTF8.self)

            var failureMessage = """
                Failed on test case: '\(testCase.failureDescription)'
                Overload: makeCounter(descriptor:labels:)
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
            client.unregisterCounter(counterWithLabels)

            // --- Test 2: The convenience `makeCounter` overload without a `labels` parameter ---
            // This should only be tested when the label set is empty.
            if testCase.labels.isEmpty {
                let counterWithoutLabels = client.makeCounter(descriptor: testCase.descriptor)
                counterWithoutLabels.increment(by: incrementValue)

                var buffer2 = [UInt8]()
                client.emit(into: &buffer2)
                let actualOutput2 = String(decoding: buffer2, as: Unicode.UTF8.self)

                failureMessage = """
                    Failed on test case: '\(testCase.failureDescription)'
                    Overload: makeCounter(descriptor:)
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
                client.unregisterCounter(counterWithoutLabels)
            }
        }
    }

}
