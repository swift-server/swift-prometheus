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

import CoreMetrics
import Foundation

/// A wrapper around ``PrometheusCollectorRegistry`` to implement the `swift-metrics` `MetricsFactory` protocol
public struct PrometheusMetricsFactory: Sendable {
    private static let _defaultRegistry = PrometheusCollectorRegistry()

    /// The default ``PrometheusCollectorRegistry``, which is used inside the ``PrometheusMetricsFactory``
    /// if no other is provided in ``init(registry:)`` or set via ``PrometheusMetricsFactory/registry``
    public static var defaultRegistry: PrometheusCollectorRegistry {
        self._defaultRegistry
    }

    /// The underlying ``PrometheusCollectorRegistry`` that is used to generate the swift-metrics handlers
    public var registry: PrometheusCollectorRegistry

    /// The default histogram buckets for a ``DurationHistogram``. If there is no explicit overwrite
    /// via ``durationHistogramBuckets``, the buckets provided here will be used for any new
    /// Swift Metrics `Timer` type.
    ///
    /// ``init(registry:)`` reads the initial value of this property from the
    /// `SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS` or
    /// `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS` environment variable, falling back to the built-in
    /// default buckets if both variables are unset or their values are malformed.
    public var defaultDurationHistogramBuckets: [Duration]

    /// The histogram buckets for a ``DurationHistogram`` per Timer label
    public var durationHistogramBuckets: [String: [Duration]]

    /// The default histogram buckets for a ``ValueHistogram``. If there is no explicit overwrite
    /// via ``valueHistogramBuckets``, the buckets provided here will be used for any new
    /// Swift Metrics `Summary` type.
    ///
    /// ``init(registry:)`` reads the initial value of this property from the
    /// `SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS` or
    /// `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS` environment variable, falling back to the built-in
    /// default buckets if both variables are unset or their values are malformed.
    public var defaultValueHistogramBuckets: [Double]

    /// The histogram buckets for a ``ValueHistogram`` per label
    public var valueHistogramBuckets: [String: [Double]]

    /// A closure to modify the name and labels used in the Swift Metrics API. This allows users
    /// to overwrite the Metric names in third party packages.
    public var nameAndLabelSanitizer:
        @Sendable (_ name: String, _ labels: [(String, String)]) -> (String, [(String, String)])

    /// Creates a new ``PrometheusMetricsFactory``.
    ///
    /// The initial values of ``defaultDurationHistogramBuckets`` and
    /// ``defaultValueHistogramBuckets`` can be configured with environment variables, allowing
    /// operators to tune the default histogram buckets without code changes:
    ///
    /// - `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS` is a comma-separated list of bucket upper bounds
    ///   used for duration and value histograms, e.g. `0.05,0.1,0.25,0.5,1,5`. Values are
    ///   interpreted as seconds for duration histograms and as raw values for value histograms.
    /// - `SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS` is a comma-separated list of bucket
    ///   upper bounds in seconds, e.g. `0.05,0.1,0.25,0.5,1,5`. If set, it takes precedence over
    ///   `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS` for duration histograms.
    /// - `SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS` is a comma-separated list of bucket
    ///   upper bounds, e.g. `5,25,100,500,1000`. If set, it takes precedence over
    ///   `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS` for value histograms.
    ///
    /// Bucket upper bounds must be finite, strictly increasing numbers. Duration bucket upper
    /// bounds must additionally be zero or greater. A variable whose value is malformed is
    /// ignored, as if it were unset. If no applicable variable provides valid buckets, the
    /// built-in default buckets are used. Buckets that
    /// are set explicitly in code, by assigning to ``defaultDurationHistogramBuckets``,
    /// ``defaultValueHistogramBuckets``, ``durationHistogramBuckets`` or
    /// ``valueHistogramBuckets``, always take precedence over the environment.
    ///
    /// - Parameter registry: The ``PrometheusCollectorRegistry`` that is used to generate the
    ///   swift-metrics handlers
    public init(registry: PrometheusCollectorRegistry = Self.defaultRegistry) {
        self.init(registry: registry, environment: { ProcessInfo.processInfo.environment[$0] })
    }

    /// Creates a new ``PrometheusMetricsFactory``, reading the default histogram buckets from
    /// the provided environment.
    ///
    /// - Parameters:
    ///   - registry: The ``PrometheusCollectorRegistry`` that is used to generate the
    ///     swift-metrics handlers
    ///   - environment: Returns the value for the given environment variable name. This is a
    ///     parameter so that tests can run without modifying the process environment.
    init(registry: PrometheusCollectorRegistry, environment: (String) -> String?) {
        self.registry = registry
        let defaultHistogramBuckets = environment(Self.histogramBucketsEnvironmentVariable)

        self.durationHistogramBuckets = [:]
        self.defaultDurationHistogramBuckets = environment(Self.durationHistogramBucketsEnvironmentVariable)
            .flatMap(Self.parseDurationHistogramBuckets)
            ?? defaultHistogramBuckets.flatMap(Self.parseDurationHistogramBuckets)
            ?? Self.builtInDurationHistogramBuckets

        self.valueHistogramBuckets = [:]
        self.defaultValueHistogramBuckets = environment(Self.valueHistogramBucketsEnvironmentVariable)
            .flatMap(Self.parseValueHistogramBuckets)
            ?? defaultHistogramBuckets.flatMap(Self.parseValueHistogramBuckets)
            ?? Self.builtInValueHistogramBuckets

        self.nameAndLabelSanitizer = { ($0, $1) }
    }
}

extension PrometheusMetricsFactory {
    static let builtInDurationHistogramBuckets: [Duration] = [
        .milliseconds(5),
        .milliseconds(10),
        .milliseconds(25),
        .milliseconds(50),
        .milliseconds(100),
        .milliseconds(250),
        .milliseconds(500),
        .seconds(1),
        .milliseconds(2500),
        .seconds(5),
        .seconds(10),
    ]

    static let builtInValueHistogramBuckets: [Double] = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]

    /// The name of the environment variable that provides the initial value of all default
    /// histogram buckets. See ``init(registry:)`` for details.
    static let histogramBucketsEnvironmentVariable =
        "SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS"

    /// The name of the environment variable that provides the initial value of
    /// ``defaultDurationHistogramBuckets``. See ``init(registry:)`` for details.
    static let durationHistogramBucketsEnvironmentVariable =
        "SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS"

    /// The name of the environment variable that provides the initial value of
    /// ``defaultValueHistogramBuckets``. See ``init(registry:)`` for details.
    static let valueHistogramBucketsEnvironmentVariable =
        "SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS"

    /// Parses a comma-separated list of histogram bucket upper bounds, e.g. `5,25,100,500`.
    ///
    /// Whitespace around values is ignored. Returns `nil` if the list is empty or contains empty
    /// segments, if a value can not be parsed as a finite `Double`, or if the values are not
    /// strictly increasing.
    static func parseValueHistogramBuckets(_ string: String) -> [Double]? {
        var buckets = [Double]()
        for var segment in string.split(separator: ",", omittingEmptySubsequences: false) {
            while segment.first?.isWhitespace == true {
                segment.removeFirst()
            }
            while segment.last?.isWhitespace == true {
                segment.removeLast()
            }
            guard let bucket = Double(segment), bucket.isFinite else {
                return nil
            }
            if let last = buckets.last, bucket <= last {
                return nil
            }
            buckets.append(bucket)
        }
        return buckets.isEmpty ? nil : buckets
    }

    /// Parses a comma-separated list of duration histogram bucket upper bounds in seconds,
    /// e.g. `0.05,0.1,0.25,0.5,1,5`.
    ///
    /// In addition to the rules of ``parseValueHistogramBuckets(_:)``, every value must be zero
    /// or greater and representable as a `Duration`.
    static func parseDurationHistogramBuckets(_ string: String) -> [Duration]? {
        guard let seconds = self.parseValueHistogramBuckets(string) else {
            return nil
        }
        var buckets = [Duration]()
        for value in seconds {
            // `Duration` counts attoseconds in an Int128; converting a `Double` beyond its range traps.
            guard value >= 0, value * 1e18 < 0x1p127 else {
                return nil
            }
            buckets.append(.seconds(value))
        }
        return buckets
    }
}

extension PrometheusMetricsFactory: CoreMetrics.MetricsFactory {
    public func makeCounter(label: String, dimensions: [(String, String)]) -> any CoreMetrics.CounterHandler {
        let (label, dimensions) = self.nameAndLabelSanitizer(label, dimensions)
        return self.registry._makeCounter(name: label, labels: dimensions, help: "")
    }

    public func makeFloatingPointCounter(
        label: String,
        dimensions: [(String, String)]
    ) -> any FloatingPointCounterHandler {
        let (label, dimensions) = self.nameAndLabelSanitizer(label, dimensions)
        return self.registry._makeCounter(name: label, labels: dimensions, help: "")
    }

    public func makeRecorder(
        label: String,
        dimensions: [(String, String)],
        aggregate: Bool
    ) -> any CoreMetrics.RecorderHandler {
        let (label, dimensions) = self.nameAndLabelSanitizer(label, dimensions)
        guard aggregate else {
            return self.registry._makeGauge(name: label, labels: dimensions, help: "")
        }
        let buckets = self.valueHistogramBuckets[label] ?? self.defaultValueHistogramBuckets
        return self.registry._makeValueHistogram(name: label, labels: dimensions, buckets: buckets, help: "")
    }

    public func makeMeter(label: String, dimensions: [(String, String)]) -> any CoreMetrics.MeterHandler {
        let (label, dimensions) = self.nameAndLabelSanitizer(label, dimensions)
        return self.registry._makeGauge(name: label, labels: dimensions, help: "")
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> any CoreMetrics.TimerHandler {
        let (label, dimensions) = self.nameAndLabelSanitizer(label, dimensions)
        let buckets = self.durationHistogramBuckets[label] ?? self.defaultDurationHistogramBuckets
        return self.registry._makeDurationHistogram(name: label, labels: dimensions, buckets: buckets, help: "")
    }

    public func destroyCounter(_ handler: any CoreMetrics.CounterHandler) {
        guard let counter = handler as? Counter else {
            return
        }
        self.registry.unregisterCounter(counter)
    }

    public func destroyFloatingPointCounter(_ handler: any FloatingPointCounterHandler) {
        guard let counter = handler as? Counter else {
            return
        }
        self.registry.unregisterCounter(counter)
    }

    public func destroyRecorder(_ handler: any CoreMetrics.RecorderHandler) {
        switch handler {
        case let gauge as Gauge:
            self.registry.unregisterGauge(gauge)
        case let histogram as Histogram<Double>:
            self.registry.unregisterValueHistogram(histogram)
        default:
            break
        }
    }

    public func destroyMeter(_ handler: any CoreMetrics.MeterHandler) {
        guard let gauge = handler as? Gauge else {
            return
        }
        self.registry.unregisterGauge(gauge)
    }

    public func destroyTimer(_ handler: any CoreMetrics.TimerHandler) {
        guard let histogram = handler as? Histogram<Duration> else {
            return
        }
        self.registry.unregisterDurationHistogram(histogram)
    }
}
