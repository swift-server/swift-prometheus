//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2018-2026 SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Configuration
import XCTest

@testable import Prometheus

@available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
final class PrometheusMetricsFactoryConfigurationTests: XCTestCase {
    private static let defaultBucketsVariable = "SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS"
    private static let durationBucketsVariable = "SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS"
    private static let valueBucketsVariable = "SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS"

    private func makeFactory(_ environment: [String: String] = [:]) -> PrometheusMetricsFactory {
        PrometheusMetricsFactory(
            registry: PrometheusCollectorRegistry(),
            configuration: ConfigReader(provider: EnvironmentVariablesProvider(environmentVariables: environment))
        )
    }

    func testExistingInitializerUsesBuiltInDefaults() {
        let factory = PrometheusMetricsFactory(registry: PrometheusCollectorRegistry())
        XCTAssertEqual(
            factory.defaultDurationHistogramBuckets,
            PrometheusMetricsFactory.builtInDurationHistogramBuckets
        )
        XCTAssertEqual(factory.defaultValueHistogramBuckets, PrometheusMetricsFactory.builtInValueHistogramBuckets)
    }

    func testInMemoryConfigurationAndProviderPrecedence() {
        let configuration = ConfigReader(providers: [
            InMemoryProvider(values: ["swift.prometheus.default.histograms": "0.5,1,5"]),
            EnvironmentVariablesProvider(environmentVariables: [Self.defaultBucketsVariable: "10,20"]),
        ])
        let factory = PrometheusMetricsFactory(configuration: configuration)
        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.milliseconds(500), .seconds(1), .seconds(5)])
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [0.5, 1, 5])
    }

    func testMalformedAndWrongTypeSpecificValuesFallBackToSharedValue() {
        let factory = PrometheusMetricsFactory(
            configuration: ConfigReader(
                provider: InMemoryProvider(values: [
                    "swift.prometheus.default.histograms": "1,2,3",
                    "swift.prometheus.default.duration.histogram.buckets": "1,,2",
                    "swift.prometheus.default.value.histogram.buckets": true,
                ])
            )
        )
        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.seconds(1), .seconds(2), .seconds(3)])
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [1, 2, 3])
    }

    func testExplicitDefaultsAndPerLabelBucketsOverrideConfiguration() {
        let registry = PrometheusCollectorRegistry()
        var factory = PrometheusMetricsFactory(
            registry: registry,
            configuration: ConfigReader(
                provider: InMemoryProvider(values: [
                    "swift.prometheus.default.histograms": "1,2,3"
                ])
            )
        )
        factory.defaultDurationHistogramBuckets = [.seconds(10)]
        factory.defaultValueHistogramBuckets = [20]
        factory.durationHistogramBuckets["custom_timer"] = [.seconds(30)]
        factory.valueHistogramBuckets["custom_value"] = [40]
        factory.makeTimer(label: "default_timer", dimensions: []).recordNanoseconds(1)
        factory.makeTimer(label: "custom_timer", dimensions: []).recordNanoseconds(1)
        factory.makeRecorder(label: "default_value", dimensions: [], aggregate: true).record(Int64(1))
        factory.makeRecorder(label: "custom_value", dimensions: [], aggregate: true).record(Int64(1))
        let output = registry.emitToString()
        XCTAssertTrue(output.contains(#"default_timer_bucket{le="10.0"} 1"#))
        XCTAssertTrue(output.contains(#"custom_timer_bucket{le="30.0"} 1"#))
        XCTAssertTrue(output.contains(#"default_value_bucket{le="20.0"} 1"#))
        XCTAssertTrue(output.contains(#"custom_value_bucket{le="40.0"} 1"#))
    }

    func testParseValueHistogramBuckets() {
        XCTAssertEqual(
            PrometheusMetricsFactory.parseValueHistogramBuckets("0.1,0.2,0.5,.75,0.9"),
            [0.1, 0.2, 0.5, 0.75, 0.9]
        )
        XCTAssertEqual(PrometheusMetricsFactory.parseValueHistogramBuckets("1"), [1])
        XCTAssertEqual(PrometheusMetricsFactory.parseValueHistogramBuckets(" 5,\t10 , 25 "), [5, 10, 25])
        XCTAssertEqual(PrometheusMetricsFactory.parseValueHistogramBuckets("1e-3,1e3"), [0.001, 1000])
        XCTAssertEqual(PrometheusMetricsFactory.parseValueHistogramBuckets("-10,-5,0,5"), [-10, -5, 0, 5])
    }

    func testParseValueHistogramBucketsRejectsMalformedInput() {
        for input in ["", " ", ",", ",1", "1,", "1,,2", "0.1;0.2", "0.1,foo", "0.1,inf", "0.1,nan"] {
            XCTAssertNil(PrometheusMetricsFactory.parseValueHistogramBuckets(input))
        }

        for input in ["1,1", "2,1"] {
            XCTAssertNil(PrometheusMetricsFactory.parseValueHistogramBuckets(input))
        }
    }

    func testParseDurationHistogramBuckets() {
        XCTAssertEqual(
            PrometheusMetricsFactory.parseDurationHistogramBuckets("0.1,0.2,0.5,.75,0.9"),
            [
                .milliseconds(100),
                .milliseconds(200),
                .milliseconds(500),
                .milliseconds(750),
                .milliseconds(900),
            ]
        )
        XCTAssertEqual(
            PrometheusMetricsFactory.parseDurationHistogramBuckets("0,1,60"),
            [.seconds(0), .seconds(1), .seconds(60)]
        )
    }

    func testParseDurationHistogramBucketsRejectsNegativeAndUnrepresentableValues() {
        XCTAssertNil(PrometheusMetricsFactory.parseDurationHistogramBuckets("-1,1"))
        // 1e300 seconds is finite but not representable as a `Duration`.
        XCTAssertNil(PrometheusMetricsFactory.parseDurationHistogramBuckets("1,1e300"))
        XCTAssertNotNil(PrometheusMetricsFactory.parseValueHistogramBuckets("1,1e300"))
    }

    func testInitReadsDefaultBucketsFromEnvironment() {
        let factory = self.makeFactory([Self.defaultBucketsVariable: "0.5,1,5"])

        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.milliseconds(500), .seconds(1), .seconds(5)])
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [0.5, 1, 5])
    }

    func testInitReadsSpecificBucketsFromEnvironment() {
        let factory = self.makeFactory([
            Self.durationBucketsVariable: "0.5,1,5",
            Self.valueBucketsVariable: "10,100,1000",
        ])

        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.milliseconds(500), .seconds(1), .seconds(5)])
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [10, 100, 1000])
    }

    func testSpecificBucketsTakePrecedenceOverDefaultBucketsEnvironment() {
        let factory = self.makeFactory([
            Self.defaultBucketsVariable: "0.5,1,5",
            Self.durationBucketsVariable: "10,20,30",
            Self.valueBucketsVariable: "100,200,300",
        ])

        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.seconds(10), .seconds(20), .seconds(30)])
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [100, 200, 300])
    }

    func testMalformedSpecificBucketsFallBackToDefaultBucketsEnvironment() {
        let factory = self.makeFactory([
            Self.defaultBucketsVariable: "0.5,1,5",
            Self.durationBucketsVariable: "oops",
        ])

        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.milliseconds(500), .seconds(1), .seconds(5)])
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [0.5, 1, 5])
    }

    func testDefaultBucketsEnvironmentAppliesPerHistogramKind() {
        // Negative upper bounds are valid for value histograms but not for duration histograms,
        // so only the value buckets are taken from the shared variable.
        let factory = self.makeFactory([Self.defaultBucketsVariable: "-5,0,5"])

        XCTAssertEqual(
            factory.defaultDurationHistogramBuckets,
            PrometheusMetricsFactory.builtInDurationHistogramBuckets
        )
        XCTAssertEqual(factory.defaultValueHistogramBuckets, [-5, 0, 5])
    }

    func testInitUsesBuiltInBucketsIfEnvironmentIsUnset() {
        let factory = self.makeFactory()

        XCTAssertEqual(
            factory.defaultDurationHistogramBuckets,
            PrometheusMetricsFactory.builtInDurationHistogramBuckets
        )
        XCTAssertEqual(factory.defaultValueHistogramBuckets, PrometheusMetricsFactory.builtInValueHistogramBuckets)
    }

    func testInitUsesBuiltInBucketsIfEnvironmentIsMalformed() {
        let factory = self.makeFactory([Self.defaultBucketsVariable: "0.5,0.1,oops"])

        XCTAssertEqual(
            factory.defaultDurationHistogramBuckets,
            PrometheusMetricsFactory.builtInDurationHistogramBuckets
        )
        XCTAssertEqual(factory.defaultValueHistogramBuckets, PrometheusMetricsFactory.builtInValueHistogramBuckets)
    }

    func testTimerUsesDurationBucketsFromEnvironment() {
        let registry = PrometheusCollectorRegistry()
        let factory = PrometheusMetricsFactory(
            registry: registry,
            configuration: ConfigReader(
                provider: EnvironmentVariablesProvider(
                    environmentVariables: [Self.defaultBucketsVariable: "0.1,0.2,0.5,.75,0.9"]
                )
            )
        )

        let timer = factory.makeTimer(label: "request_duration_seconds", dimensions: [])
        timer.recordNanoseconds(300_000_000)  // 300ms

        let output = registry.emitToString()
        XCTAssertTrue(output.contains(#"request_duration_seconds_bucket{le="0.5"} 1"#))
        XCTAssertTrue(output.contains(#"request_duration_seconds_sum 0.3"#))
    }

    func testExplicitlyConfiguredBucketsTakePrecedenceOverEnvironment() {
        let registry = PrometheusCollectorRegistry()
        var factory = PrometheusMetricsFactory(
            registry: registry,
            configuration: ConfigReader(
                provider: EnvironmentVariablesProvider(
                    environmentVariables: [Self.defaultBucketsVariable: "1,2,3"]
                )
            )
        )
        factory.durationHistogramBuckets["explicitly_configured"] = [.seconds(10)]

        XCTAssertEqual(factory.defaultDurationHistogramBuckets, [.seconds(1), .seconds(2), .seconds(3)])

        let timer = factory.makeTimer(label: "explicitly_configured", dimensions: [])
        timer.recordNanoseconds(1)

        XCTAssertTrue(registry.emitToString().contains(#"explicitly_configured_bucket{le="10.0"} 1"#))
    }
}
