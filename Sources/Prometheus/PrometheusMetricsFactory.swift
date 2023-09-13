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

/// A wrapper around ``PrometheusClient`` to implement the `swift-metrics` `MetricsFactory` protocol
public struct PrometheusMetricsFactory: Sendable {

    /// The underlying ``PrometheusClient`` that is used to generate
    public var client: PrometheusCollectorRegistry

    /// The histogram buckets for a ``TimeHistogram``
    public var defaultTimeHistogramBuckets: [Duration]

    /// The histogram buckets for a ``TimeHistogram`` per Timer label
    public var timeHistogramBuckets: [String: [Duration]]

    /// The default histogram buckets for a ``ValueHistogram``. If there is no explicit overwrite
    /// via ``valueHistogramBuckets``, the buckets provided here will be used for any new
    /// Swift Metrics Summary type.
    public var defaultValueHistogramBuckets: [Double]

    public var valueHistogramBuckets: [String: [Double]]

    public var labelAndDimensionSanitizer: @Sendable (_ label: String, _ dimensions: [(String, String)]) -> (String, [(String, String)])

    public init(client: PrometheusCollectorRegistry) {
        self.client = client

        self.timeHistogramBuckets = [:]
        self.defaultTimeHistogramBuckets = [
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

        self.valueHistogramBuckets = [:]
        self.defaultValueHistogramBuckets = [
            5,
            10,
            25,
            50,
            100,
            250,
            500,
            1000,
            2500,
            5000,
            10000
        ]

        self.labelAndDimensionSanitizer = { ($0, $1) }
    }
}

extension PrometheusMetricsFactory: CoreMetrics.MetricsFactory {
    public func makeCounter(label: String, dimensions: [(String, String)]) -> CoreMetrics.CounterHandler {
        let (label, dimensions) = self.labelAndDimensionSanitizer(label, dimensions)
        return self.client.makeCounter(name: label, labels: dimensions)
    }

    public func makeFloatingPointCounter(label: String, dimensions: [(String, String)]) -> FloatingPointCounterHandler {
        let (label, dimensions) = self.labelAndDimensionSanitizer(label, dimensions)
        return self.client.makeCounter(name: label, labels: dimensions)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> CoreMetrics.RecorderHandler {
        let (label, dimensions) = self.labelAndDimensionSanitizer(label, dimensions)
        if aggregate {
            let buckets = self.valueHistogramBuckets[label] ?? self.defaultValueHistogramBuckets
            return self.client.makeValueHistogram(name: label, labels: dimensions, buckets: buckets)
        } else {
            return self.client.makeGauge(name: label, labels: dimensions)
        }
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> CoreMetrics.TimerHandler {
        let (label, dimensions) = self.labelAndDimensionSanitizer(label, dimensions)
        let buckets = self.timeHistogramBuckets[label] ?? self.defaultTimeHistogramBuckets
        return self.client.makeTimeHistogram(name: label, labels: dimensions, buckets: buckets)
    }

    public func destroyCounter(_ handler: CoreMetrics.CounterHandler) {
        guard let counter = handler as? Counter else {
            return
        }
        self.client.destroyCounter(counter)
    }

    public func destroyFloatingPointCounter(_ handler: FloatingPointCounterHandler) {
        guard let counter = handler as? Counter else {
            return
        }
        self.client.destroyCounter(counter)
    }

    public func destroyRecorder(_ handler: CoreMetrics.RecorderHandler) {
        switch handler {
        case let gauge as Gauge:
            self.client.destroyGauge(gauge)
        case let histogram as Histogram<Double>:
            self.client.destroyValueHistogram(histogram)
        default:
            break
        }
    }

    public func destroyTimer(_ handler: CoreMetrics.TimerHandler) {
        guard let histogram = handler as? Histogram<Duration> else {
            return
        }
        self.client.destroyTimeHistogram(histogram)
    }
}
