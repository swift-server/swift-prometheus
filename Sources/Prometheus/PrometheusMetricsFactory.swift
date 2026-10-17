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

import Configuration
import CoreMetrics

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
    public var defaultDurationHistogramBuckets: [Duration]

    /// The histogram buckets for a ``DurationHistogram`` per Timer label
    public var durationHistogramBuckets: [String: [Duration]]

    /// The default histogram buckets for a ``ValueHistogram``. If there is no explicit overwrite
    /// via ``valueHistogramBuckets``, the buckets provided here will be used for any new
    /// Swift Metrics `Summary` type.
    public var defaultValueHistogramBuckets: [Double]

    /// The histogram buckets for a ``ValueHistogram`` per label
    public var valueHistogramBuckets: [String: [Double]]

    /// A closure to modify the name and labels used in the Swift Metrics API. This allows users
    /// to overwrite the Metric names in third party packages.
    public var nameAndLabelSanitizer:
        @Sendable (_ name: String, _ labels: [(String, String)]) -> (String, [(String, String)])

    /// Creates a factory with built-in default buckets, without reading configuration.
    ///
    /// - Parameter registry: The registry used to generate the swift-metrics handlers.
    public init(registry: PrometheusCollectorRegistry = Self.defaultRegistry) {
        self.registry = registry
        self.durationHistogramBuckets = [:]
        self.defaultDurationHistogramBuckets = Self.builtInDurationHistogramBuckets
        self.valueHistogramBuckets = [:]
        self.defaultValueHistogramBuckets = Self.builtInValueHistogramBuckets
        self.nameAndLabelSanitizer = { ($0, $1) }
    }

    /// Creates a factory with default histogram buckets read from configuration.
    ///
    /// Configuration is read once during initialization. Values are comma-separated strings
    /// of bucket upper bounds, interpreted as seconds for durations and raw values otherwise:
    ///
    /// - `swift.prometheus.default.histograms`: Shared defaults for both histogram kinds.
    /// - `swift.prometheus.default.duration.histogram.buckets`: Duration-specific defaults.
    /// - `swift.prometheus.default.value.histogram.buckets`: Value-specific defaults.
    ///
    /// With `EnvironmentVariablesProvider`, these keys map to
    /// `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAMS`,
    /// `SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS`, and
    /// `SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS`, respectively.
    ///
    /// Bounds must be finite and strictly increasing. Duration bounds must also be nonnegative
    /// and representable as `Duration`. Missing or malformed specific values fall back to the
    /// shared value, then to built-in defaults. Values that cannot be read as strings are ignored.
    /// Assignments to the default bucket properties or per-label bucket dictionaries after
    /// initialization take precedence over configuration.
    ///
    /// - Parameters:
    ///   - registry: The registry used to generate the swift-metrics handlers.
    ///   - configuration: The reader supplying configuration from application-selected providers.
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(
        registry: PrometheusCollectorRegistry = Self.defaultRegistry,
        configuration: ConfigReader
    ) {
        self.init(registry: registry)
        let shared = configuration.string(forKey: "swift.prometheus.default.histograms")
        self.defaultDurationHistogramBuckets =
            configuration.string(
                forKey: "swift.prometheus.default.duration.histogram.buckets"
            ).flatMap(Self.parseDurationHistogramBuckets)
            ?? shared.flatMap(Self.parseDurationHistogramBuckets)
            ?? Self.builtInDurationHistogramBuckets
        self.defaultValueHistogramBuckets =
            configuration.string(
                forKey: "swift.prometheus.default.value.histogram.buckets"
            ).flatMap(Self.parseValueHistogramBuckets)
            ?? shared.flatMap(Self.parseValueHistogramBuckets)
            ?? Self.builtInValueHistogramBuckets
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
