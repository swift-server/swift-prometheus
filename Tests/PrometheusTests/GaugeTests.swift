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

    func testWithMetricNameDescriptorWithFullComponentMatrix() {
        // --- Test Constants ---
        // let helpTextValue = "https://help.url/sub"
        let metricName = "foo2"
        let incrementValue: Double = 1.0
        let client = PrometheusCollectorRegistry()

        // 1. Define the base naming combinations first.
        let baseNameCases:
            [(
                namespace: String?, subsystem: String?, unitName: String?, expectedMetricName: String,
                description: String
            )] = [
                (
                    namespace: "myapp", subsystem: "subsystem", unitName: "bytes",
                    expectedMetricName: "myapp_subsystem_foo2_bytes", description: "All components present"
                ),
                (
                    namespace: "myapp", subsystem: "subsystem", unitName: nil,
                    expectedMetricName: "myapp_subsystem_foo2", description: "Unit is nil"
                ),
                (
                    namespace: "myapp", subsystem: nil, unitName: "bytes", expectedMetricName: "myapp_foo2_bytes",
                    description: "Subsystem is nil"
                ),
                (
                    namespace: "myapp", subsystem: nil, unitName: nil, expectedMetricName: "myapp_foo2",
                    description: "Subsystem and Unit are nil"
                ),
                (
                    namespace: nil, subsystem: "subsystem", unitName: "bytes",
                    expectedMetricName: "subsystem_foo2_bytes", description: "Namespace is nil"
                ),
                (
                    namespace: nil, subsystem: "subsystem", unitName: nil, expectedMetricName: "subsystem_foo2",
                    description: "Namespace and Unit are nil"
                ),
                (
                    namespace: nil, subsystem: nil, unitName: "bytes", expectedMetricName: "foo2_bytes",
                    description: "Namespace and Subsystem are nil"
                ),
                (
                    namespace: nil, subsystem: nil, unitName: nil, expectedMetricName: "foo2",
                    description: "Only metric name is present"
                ),
                (
                    namespace: "", subsystem: "subsystem", unitName: "bytes",
                    expectedMetricName: "subsystem_foo2_bytes", description: "Namespace is empty string"
                ),
                (
                    namespace: "myapp", subsystem: "", unitName: "bytes", expectedMetricName: "myapp_foo2_bytes",
                    description: "Subsystem is empty string"
                ),
                (
                    namespace: "myapp", subsystem: "subsystem", unitName: "",
                    expectedMetricName: "myapp_subsystem_foo2", description: "Unit is empty string"
                ),
                (
                    namespace: "", subsystem: "", unitName: "bytes", expectedMetricName: "foo2_bytes",
                    description: "Namespace and Subsystem are empty strings"
                ),
                (
                    namespace: "myapp", subsystem: "", unitName: "", expectedMetricName: "myapp_foo2",
                    description: "Subsystem and Unit are empty strings"
                ),
                (
                    namespace: "", subsystem: "subsystem", unitName: "", expectedMetricName: "subsystem_foo2",
                    description: "Namespace and Unit are empty strings"
                ),
                (
                    namespace: "", subsystem: "", unitName: "", expectedMetricName: "foo2",
                    description: "All optional components are empty strings"
                ),
            ]

        // 2. Define the label combinations to test.
        let labelCases: [(labels: [(String, String)], expectedLabelString: String, description: String)] = [
            (labels: [], expectedLabelString: "", description: "without labels"),
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

                // Case: Without help text (helpText is nil)
                allTestCases.append(
                    (
                        descriptor: MetricNameDescriptor(
                            namespace: nameCase.namespace,
                            subsystem: nameCase.subsystem,
                            metricName: metricName,
                            unitName: nameCase.unitName,
                            helpText: nil
                        ),
                        labels: labelCase.labels,
                        expectedOutput: """
                        # TYPE \(nameCase.expectedMetricName) gauge
                        \(expectedMetricLine)

                        """,
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
