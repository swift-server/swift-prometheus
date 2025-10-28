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

/// A promtheus collector registry to create and store collectors.
///
/// It creates and stores collectors. Further you can use the ``PrometheusCollectorRegistry/emit(into:)``
/// method to export the metrics form registered collectors into a Prometheus compatible format.
///
/// To use a ``PrometheusCollectorRegistry`` with `swift-metrics` use the ``PrometheusMetricsFactory``.
public final class PrometheusCollectorRegistry: Sendable {
    private struct LabelsKey: Hashable, Sendable {
        var labels: [(String, String)]

        init(_ labels: [(String, String)]) {
            self.labels = labels
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.labels.count == rhs.labels.count else { return false }

            for (lhs, rhs) in zip(lhs.labels, rhs.labels) {
                guard lhs.0 == rhs.0 && lhs.1 == rhs.1 else {
                    return false
                }
            }
            return true
        }

        func hash(into hasher: inout Hasher) {
            for (key, value) in self.labels {
                key.hash(into: &hasher)
                value.hash(into: &hasher)
            }
        }
    }

    private enum HistogramBuckets: Sendable, Hashable {
        case duration([Duration])
        case value([Double])
    }

    /// A MetricFamily.
    ///
    /// A metric name can either map to multiple labeled metrics OR a single unlabeled metric,
    /// but not both simultaneously to ensure proper Prometheus aggregations.
    /// All metrics with the same name must have identical help text for consistency.
    /// For histograms, the buckets are immutable for a MetricFamily once initialized with the first
    /// metric. See also https://github.com/prometheus/OpenMetrics/issues/197.
    private struct MetricFamily<Metric: Sendable & AnyObject>: Sendable {
        private enum State {
            case labeled([LabelsKey: Metric])
            case unlabeled(Metric)
            case empty
        }

        let buckets: HistogramBuckets?
        let help: String?
        private let state: State

        init(
            metricsByLabelSets: [LabelsKey: Metric] = [:],
            buckets: HistogramBuckets? = nil,
            help: String? = nil,
            metricUnlabeled: Metric? = nil
        ) {
            // Validate mutual exclusivity on creation.
            if metricUnlabeled != nil && !metricsByLabelSets.isEmpty {
                fatalError("Cannot have both labeled and unlabeled metrics in the same family.")
            }

            self.buckets = buckets
            self.help = help

            // Set internal state based on inputs.
            if let unlabeled = metricUnlabeled {
                self.state = .unlabeled(unlabeled)
            } else if !metricsByLabelSets.isEmpty {
                self.state = .labeled(metricsByLabelSets)
            } else {
                self.state = .empty
            }
        }

        func adding(metric: Metric, for labels: [(String, String)]) -> MetricFamily<Metric> {
            guard !labels.isEmpty else {
                fatalError("Use initializer for unlabeled metrics, not adding method")
            }

            switch state {
            case .unlabeled:
                fatalError("Cannot register a labeled metric when an unlabeled metric already exists.")
            case .labeled(let existingMetrics):
                let labelsKey = LabelsKey(labels)
                guard existingMetrics[labelsKey] == nil else {
                    return self
                }

                var newMetricsByLabelSets = existingMetrics
                newMetricsByLabelSets[labelsKey] = metric

                return MetricFamily(
                    metricsByLabelSets: newMetricsByLabelSets,
                    buckets: buckets,
                    help: help,
                    metricUnlabeled: nil
                )
            case .empty:
                let labelsKey = LabelsKey(labels)
                return MetricFamily(
                    metricsByLabelSets: [labelsKey: metric],
                    buckets: buckets,
                    help: help,
                    metricUnlabeled: nil
                )
            }
        }

        func removing(metric: Metric, for labels: [(String, String)]) -> MetricFamily<Metric>? {
            switch state {
            case .unlabeled(let unlabeledMetric):
                if labels.isEmpty && unlabeledMetric === metric {
                    return nil  // Remove entire family.
                }
                return self  // Metric not found, return unchanged.

            case .labeled(let labeledMetrics):
                let key = LabelsKey(labels)
                guard let existingMetric = labeledMetrics[key],
                    existingMetric === metric
                else {
                    return self  // Metric not found, return unchanged.
                }

                var newMetricsByLabelSets = labeledMetrics
                newMetricsByLabelSets.removeValue(forKey: key)

                guard newMetricsByLabelSets.isEmpty else {
                    return MetricFamily(
                        metricsByLabelSets: newMetricsByLabelSets,
                        buckets: buckets,
                        help: help,
                        metricUnlabeled: nil
                    )
                }
                return nil  // Remove entire family.

            case .empty:
                return self  // Nothing to remove.
            }
        }

        func getMetric(for labels: [(String, String)]) -> Metric? {
            switch state {
            case .labeled(let metrics):
                return metrics[LabelsKey(labels)]
            case .unlabeled(let metric):
                return labels.isEmpty ? metric : nil
            case .empty:
                return nil
            }
        }

        func forEachMetric(_ closure: (Metric) -> Void) {
            switch state {
            case .unlabeled(let metric):
                closure(metric)
            case .labeled(let metrics):
                for metric in metrics.values {
                    closure(metric)
                }
            case .empty:
                break
            }
        }
    }

    private enum Metric {
        case counter(MetricFamily<Counter>)
        case gauge(MetricFamily<Gauge>)
        case durationHistogram(MetricFamily<DurationHistogram>)
        case valueHistogram(MetricFamily<ValueHistogram>)
    }

    private let box = NIOLockedValueBox([String: Metric]())

    /// Creates a new PrometheusCollectorRegistry with default configuration.
    ///
    /// Uses deduplication for TYPE and HELP lines according to Prometheus specifications,
    /// where only one TYPE and HELP line is emitted per metric name regardless of label sets.
    public init() {}

    // MARK: Creating Metrics

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Counter``'s value.
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeCounter(descriptor:)` instead.")
    public func makeCounter(name: String, help: String) -> Counter {
        return self._makeCounter(name: name, labels: [], help: help)
    }

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Counter``'s value.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeCounter(descriptor:)` instead.")
    public func makeCounter(name: String) -> Counter {
        return self._makeCounter(name: name, labels: [], help: "")
    }

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeCounter(descriptor: MetricNameDescriptor) -> Counter {
        return self._makeCounter(name: descriptor.name, labels: [], help: descriptor.helpText ?? "")
    }

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Counter``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeCounter(descriptor:labels:)` instead.")
    public func makeCounter(name: String, labels: [(String, String)], help: String) -> Counter {
        return self._makeCounter(name: name, labels: labels, help: help)
    }

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Counter``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeCounter(descriptor:labels:)` instead.")
    public func makeCounter(name: String, labels: [(String, String)]) -> Counter {
        return self._makeCounter(name: name, labels: labels, help: "")
    }

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeCounter(descriptor: MetricNameDescriptor, labels: [(String, String)]) -> Counter {
        return self._makeCounter(name: descriptor.name, labels: labels, help: descriptor.helpText ?? "")
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeGauge(descriptor:)` instead.")
    public func makeGauge(name: String, help: String) -> Gauge {
        return self._makeGauge(name: name, labels: [], help: help)
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeGauge(descriptor:)` instead.")
    public func makeGauge(name: String) -> Gauge {
        return self._makeGauge(name: name, labels: [], help: "")
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(descriptor: MetricNameDescriptor) -> Gauge {
        return self._makeGauge(name: descriptor.name, labels: [], help: descriptor.helpText ?? "")
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeGauge(descriptor:labels:)` instead.")
    public func makeGauge(name: String, labels: [(String, String)], help: String) -> Gauge {
        return self._makeGauge(name: name, labels: labels, help: help)
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeGauge(descriptor:labels:)` instead.")
    public func makeGauge(name: String, labels: [(String, String)]) -> Gauge {
        return self._makeGauge(name: name, labels: labels, help: "")
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name and labels,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(descriptor: MetricNameDescriptor, labels: [(String, String)]) -> Gauge {
        return self._makeGauge(name: descriptor.name, labels: labels, help: descriptor.helpText ?? "")
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``DurationHistogram``'s value.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeDurationHistogram(descriptor:buckets:)` instead.")
    public func makeDurationHistogram(name: String, buckets: [Duration], help: String) -> DurationHistogram {
        return self._makeDurationHistogram(name: name, labels: [], buckets: buckets, help: help)
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``DurationHistogram``'s value.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeDurationHistogram(descriptor:buckets:)` instead.")
    public func makeDurationHistogram(name: String, buckets: [Duration]) -> DurationHistogram {
        return self._makeDurationHistogram(name: name, labels: [], buckets: buckets, help: "")
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeDurationHistogram(descriptor: MetricNameDescriptor, buckets: [Duration]) -> DurationHistogram {
        return self._makeDurationHistogram(
            name: descriptor.name,
            labels: [],
            buckets: buckets,
            help: descriptor.helpText ?? ""
        )
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``DurationHistogram``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeDurationHistogram(descriptor:labels:buckets:)` instead.")
    public func makeDurationHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Duration],
        help: String
    ) -> DurationHistogram {
        return self._makeDurationHistogram(
            name: name,
            labels: labels,
            buckets: buckets,
            help: help
        )
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``DurationHistogram``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeDurationHistogram(descriptor:labels:buckets:)` instead.")
    public func makeDurationHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Duration]
    ) -> DurationHistogram {
        return self._makeDurationHistogram(
            name: name,
            labels: labels,
            buckets: buckets,
            help: ""
        )
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name and labels,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeDurationHistogram(
        descriptor: MetricNameDescriptor,
        labels: [(String, String)],
        buckets: [Duration]
    ) -> DurationHistogram {
        return self._makeDurationHistogram(
            name: descriptor.name,
            labels: labels,
            buckets: buckets,
            help: descriptor.helpText ?? ""
        )
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``ValueHistogram``'s value.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeValueHistogram(descriptor:buckets:)` instead.")
    public func makeValueHistogram(name: String, buckets: [Double], help: String) -> ValueHistogram {
        return self._makeValueHistogram(name: name, labels: [], buckets: buckets, help: help)
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``ValueHistogram``'s value.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeValueHistogram(descriptor:buckets:)` instead.")
    public func makeValueHistogram(name: String, buckets: [Double]) -> ValueHistogram {
        return self._makeValueHistogram(name: name, labels: [], buckets: buckets, help: "")
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeValueHistogram(descriptor: MetricNameDescriptor, buckets: [Double]) -> ValueHistogram {
        return self._makeValueHistogram(
            name: descriptor.name,
            labels: [],
            buckets: buckets,
            help: descriptor.helpText ?? ""
        )
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``ValueHistogram``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Parameter help: Help text for the metric. If a non-empty string is provided, it will be emitted as a `# HELP` line in the exposition format.
    ///                   If the parameter is omitted or an empty string is passed, the `# HELP` line will not be generated for this metric.
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeValueHistogram(descriptor:labels:buckets:)` instead.")
    public func makeValueHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Double],
        help: String
    ) -> ValueHistogram {
        return self._makeValueHistogram(
            name: name,
            labels: labels,
            buckets: buckets,
            help: help
        )
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``ValueHistogram``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    @available(*, deprecated, message: "Use `makeValueHistogram(descriptor:labels:buckets:)` instead.")
    public func makeValueHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Double]
    ) -> ValueHistogram {
        return self._makeValueHistogram(
            name: name,
            labels: labels,
            buckets: buckets,
            help: ""
        )
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name and labels,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeValueHistogram(
        descriptor: MetricNameDescriptor,
        labels: [(String, String)],
        buckets: [Double]
    ) -> ValueHistogram {
        return self._makeValueHistogram(
            name: descriptor.name,
            labels: labels,
            buckets: buckets,
            help: descriptor.helpText ?? ""
        )
    }

    // MARK: - Private Implementation

    internal func _makeCounter(name: String, labels: [(String, String)], help: String) -> Counter {
        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()
        let key = LabelsKey(labels)

        return self.box.withLockedValue { store -> Counter in
            guard let entry = store[name] else {
                // First time a Counter is registered with this name.
                let counter = Counter(name: name, labels: labels)
                let counterFamily = MetricFamily(
                    metricsByLabelSets: labels.isEmpty ? [:] : [key: counter],
                    help: help,
                    metricUnlabeled: labels.isEmpty ? counter : nil
                )
                store[name] = .counter(counterFamily)
                return counter
            }

            switch entry {
            case .counter(let existingCounterFamily):

                // Validate help text consistency. While Prometheus wouldn't break with duplicate and distinct
                // HELP lines, the client enforces uniqueness and consistency.
                if let existingHelp = existingCounterFamily.help, existingHelp != help {
                    fatalError(
                        """
                        Help text mismatch for metric '\(name)':
                        Existing help: '\(existingHelp)'
                        New help: '\(help)'
                        All metrics with the same name must have identical help text.
                        """
                    )
                }

                if let existingCounter = existingCounterFamily.getMetric(for: labels) {
                    return existingCounter
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let counter = Counter(name: name, labels: labels)
                let updatedFamily = existingCounterFamily.adding(metric: counter, for: labels)

                // Write the modified entry back to the store.
                store[name] = .counter(updatedFamily)

                return counter

            default:
                // A metric with this name exists, but it's not a Counter. This is a programming error.
                // While Prometheus wouldn't stop you, it may result in unpredictable behavior with tools like Grafana or PromQL.
                fatalError(
                    """
                    Metric type mismatch:
                    Could not register a Counter with name '\(name)',
                    since a different metric type (\(entry.self)) was already registered with this name.
                    """
                )
            }
        }
    }

    internal func _makeGauge(name: String, labels: [(String, String)], help: String) -> Gauge {
        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()
        let key = LabelsKey(labels)

        return self.box.withLockedValue { store -> Gauge in
            guard let entry = store[name] else {
                // First time a Gauge is registered with this name.
                let gauge = Gauge(name: name, labels: labels)
                let gaugeFamily = MetricFamily(
                    metricsByLabelSets: labels.isEmpty ? [:] : [key: gauge],
                    help: help,
                    metricUnlabeled: labels.isEmpty ? gauge : nil
                )
                store[name] = .gauge(gaugeFamily)
                return gauge
            }

            switch entry {
            case .gauge(let existingGaugeFamily):

                // Validate help text consistency. While Prometheus wouldn't break with duplicate and distinct
                // HELP lines, the client enforces uniqueness and consistency.
                if let existingHelp = existingGaugeFamily.help, existingHelp != help {
                    fatalError(
                        """
                        Help text mismatch for metric '\(name)':
                        Existing help: '\(existingHelp)'
                        New help: '\(help)'
                        All metrics with the same name must have identical help text.
                        """
                    )
                }

                if let existingGauge = existingGaugeFamily.getMetric(for: labels) {
                    return existingGauge
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let gauge = Gauge(name: name, labels: labels)
                let updatedFamily = existingGaugeFamily.adding(metric: gauge, for: labels)

                // Write the modified entry back to the store.
                store[name] = .gauge(updatedFamily)

                return gauge

            default:
                // A metric with this name exists, but it's not a Gauge. This is a programming error.
                // While Prometheus wouldn't stop you, it may result in unpredictable behavior with tools like Grafana or PromQL.
                fatalError(
                    """
                    Metric type mismatch:
                    Could not register a Gauge with name '\(name)',
                    since a different metric type (\(entry.self)) was already registered with this name.
                    """
                )
            }
        }
    }

    internal func _makeDurationHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Duration],
        help: String
    ) -> DurationHistogram {
        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()
        let key = LabelsKey(labels)

        return self.box.withLockedValue { store -> DurationHistogram in
            guard let entry = store[name] else {
                // First time a DurationHistogram is registered with this name. This defines the buckets.
                let histogram = DurationHistogram(name: name, labels: labels, buckets: buckets)
                let histogramFamily = MetricFamily(
                    metricsByLabelSets: labels.isEmpty ? [:] : [key: histogram],
                    buckets: .duration(buckets),
                    help: help,
                    metricUnlabeled: labels.isEmpty ? histogram : nil
                )
                store[name] = .durationHistogram(histogramFamily)
                return histogram
            }

            switch entry {
            case .durationHistogram(let existingHistogramFamily):

                // Validate help text consistency. While Prometheus wouldn't break with duplicate and distinct
                // HELP lines, the client enforces uniqueness and consistency.
                if let existingHelp = existingHistogramFamily.help, existingHelp != help {
                    fatalError(
                        """
                        Help text mismatch for metric '\(name)':
                        Existing help: '\(existingHelp)'
                        New help: '\(help)'
                        All metrics with the same name must have identical help text.
                        """
                    )
                }

                // Validate buckets match the stored ones.
                if case .duration(let storedBuckets) = existingHistogramFamily.buckets {
                    guard storedBuckets == buckets else {
                        fatalError(
                            """
                            Bucket mismatch for DurationHistogram '\(name)':
                            Expected buckets: \(storedBuckets)
                            Provided buckets: \(buckets)
                            All metrics with the same name must use identical buckets.
                            """
                        )
                    }
                }

                if let existingHistogram = existingHistogramFamily.getMetric(for: labels) {
                    return existingHistogram
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let histogram = DurationHistogram(name: name, labels: labels, buckets: buckets)
                let updatedFamily = existingHistogramFamily.adding(metric: histogram, for: labels)

                // Write the modified entry back to the store.
                store[name] = .durationHistogram(updatedFamily)

                return histogram

            default:
                // A metric with this name exists, but it's not a DurationHistogram. This is a programming error.
                // While Prometheus wouldn't stop you, it may result in unpredictable behavior with tools like Grafana or PromQL.
                fatalError(
                    """
                    Metric type mismatch:
                    Could not register a DurationHistogram with name '\(name)',
                    since a different metric type (\(entry.self)) was already registered with this name.
                    """
                )
            }
        }
    }

    internal func _makeValueHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Double],
        help: String
    ) -> ValueHistogram {
        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()
        let key = LabelsKey(labels)

        return self.box.withLockedValue { store -> ValueHistogram in
            guard let entry = store[name] else {
                // First time a ValueHistogram is registered with this name. This defines the buckets.
                let histogram = ValueHistogram(name: name, labels: labels, buckets: buckets)
                let histogramFamily = MetricFamily(
                    metricsByLabelSets: labels.isEmpty ? [:] : [key: histogram],
                    buckets: .value(buckets),
                    help: help,
                    metricUnlabeled: labels.isEmpty ? histogram : nil
                )
                store[name] = .valueHistogram(histogramFamily)
                return histogram
            }

            switch entry {
            case .valueHistogram(let existingHistogramFamily):

                // Validate help text consistency. While Prometheus wouldn't break with duplicate and distinct
                // HELP lines, the client enforces uniqueness and consistency.
                if let existingHelp = existingHistogramFamily.help, existingHelp != help {
                    fatalError(
                        """
                        Help text mismatch for metric '\(name)':
                        Existing help: '\(existingHelp)'
                        New help: '\(help)'
                        All metrics with the same name must have identical help text.
                        """
                    )
                }
                // Validate buckets match the stored ones.
                if case .value(let storedBuckets) = existingHistogramFamily.buckets {
                    guard storedBuckets == buckets else {
                        fatalError(
                            """
                            Bucket mismatch for ValueHistogram '\(name)':
                            Expected buckets: \(storedBuckets)
                            Provided buckets: \(buckets)
                            All metrics with the same name must use identical buckets.
                            """
                        )
                    }
                }

                if let existingHistogram = existingHistogramFamily.getMetric(for: labels) {
                    return existingHistogram
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let histogram = ValueHistogram(name: name, labels: labels, buckets: buckets)
                let updatedFamily = existingHistogramFamily.adding(metric: histogram, for: labels)

                // Write the modified entry back to the store.
                store[name] = .valueHistogram(updatedFamily)

                return histogram

            default:
                // A metric with this name exists, but it's not a ValueHistogram. This is a programming error.
                // While Prometheus wouldn't stop you, it may result in unpredictable behavior with tools like Grafana or PromQL.
                fatalError(
                    """
                    Metric type mismatch:
                    Could not register a ValueHistogram with name '\(name)',
                    since a different metric type (\(entry.self)) was already registered with this name.
                    """
                )
            }
        }
    }

    // MARK: Destroying Metrics

    /// Unregisters a ``Counter`` from the ``PrometheusCollectorRegistry``. This means that the provided ``Counter``
    /// will not be included in future ``emit(into:)`` calls.
    ///
    /// - Note: If the provided ``Counter`` is unknown to the registry this function call will be ignored
    /// - Parameter counter: The ``Counter`` that shall be removed from the registry
    public func unregisterCounter(_ counter: Counter) {
        self.box.withLockedValue { store in
            switch store[counter.name] {
            case .counter(let counterFamily):
                if let updatedFamily = counterFamily.removing(metric: counter, for: counter.labels) {
                    store[counter.name] = .counter(updatedFamily)
                } else {
                    // Remove the entire family.
                    store.removeValue(forKey: counter.name)
                }
            default:
                return
            }
        }
    }

    /// Unregisters a ``Gauge`` from the ``PrometheusCollectorRegistry``. This means that the provided ``Gauge``
    /// will not be included in future ``emit(into:)`` calls.
    ///
    /// - Note: If the provided ``Gauge`` is unknown to the registry this function call will be ignored
    /// - Parameter gauge: The ``Gauge`` that shall be removed from the registry
    public func unregisterGauge(_ gauge: Gauge) {
        self.box.withLockedValue { store in
            switch store[gauge.name] {
            case .gauge(let gaugeFamily):
                if let updatedFamily = gaugeFamily.removing(metric: gauge, for: gauge.labels) {
                    store[gauge.name] = .gauge(updatedFamily)
                } else {
                    // Remove the entire family.
                    store.removeValue(forKey: gauge.name)
                }
            default:
                return
            }
        }
    }

    /// Unregisters a ``DurationHistogram`` from the ``PrometheusCollectorRegistry``. This means that this ``DurationHistogram``
    /// will not be included in future ``emit(into:)`` calls.
    ///
    /// - Note: If the provided ``DurationHistogram`` is unknown to the registry this function call will be ignored
    /// - Parameter histogram: The ``DurationHistogram`` that shall be removed from the registry
    public func unregisterDurationHistogram(_ histogram: DurationHistogram) {
        self.box.withLockedValue { store in
            switch store[histogram.name] {
            case .durationHistogram(let histogramFamily):
                if let updatedFamily = histogramFamily.removing(metric: histogram, for: histogram.labels) {
                    store[histogram.name] = .durationHistogram(updatedFamily)
                } else {
                    // Remove the entire family.
                    store.removeValue(forKey: histogram.name)
                }
            default:
                return
            }
        }
    }

    /// Unregisters a ``ValueHistogram`` from the ``PrometheusCollectorRegistry``. This means that this ``ValueHistogram``
    /// will not be included in future ``emit(into:)`` calls.
    ///
    /// - Note: If the provided ``ValueHistogram`` is unknown to the registry this function call will be ignored
    /// - Parameter histogram: The ``ValueHistogram`` that shall be removed from the registry
    public func unregisterValueHistogram(_ histogram: ValueHistogram) {
        self.box.withLockedValue { store in
            switch store[histogram.name] {
            case .valueHistogram(let histogramFamily):
                if let updatedFamily = histogramFamily.removing(metric: histogram, for: histogram.labels) {
                    store[histogram.name] = .valueHistogram(updatedFamily)
                } else {
                    // Remove the entire family.
                    store.removeValue(forKey: histogram.name)
                }
            default:
                return
            }
        }
    }

    // MARK: Emitting

    private let bufferBox = NIOLockedValueBox([UInt8]())

    /// Resets the internal buffer used by ``emitToString()`` and ``emitToBuffer()``.
    ///
    /// Forces the buffer capacity back to 0, which will trigger re-calibration on the next emission call.
    /// This is useful when the registry's metric composition has changed significantly and you want to
    /// optimize buffer size for the new workload.
    ///
    /// - Note: Does not affect ``emit(into:)`` calls which use external buffers
    public func resetInternalBuffer() {
        bufferBox.withLockedValue { buffer in
            // Resets capacity to 0, forcing re-calibration
            buffer.removeAll()
        }
    }

    /// Returns the current capacity of the internal buffer used by ``emitToString()`` and ``emitToBuffer()``.
    ///
    /// The capacity represents the allocated memory size, not the current content length. A capacity of 0
    /// indicates the buffer will auto-size on the next emission call. The capacity may grow over time as
    /// the registry's output requirements increase.
    ///
    /// - Returns: The current buffer capacity in bytes
    /// - Note: Primarily useful for testing and monitoring buffer behavior
    public func internalBufferCapacity() -> Int {
        return bufferBox.withLockedValue { buffer in
            buffer.capacity
        }
    }

    /// Emits all registered metrics in Prometheus text format as a String.
    ///
    /// Uses an internal buffer that auto-sizes on first call to find optimal initial capacity. The buffer
    /// may resize during the registry's lifetime if output grows significantly. Subsequent calls reuse the
    /// established capacity, clearing content but preserving the initially allocated memory.
    ///
    /// - Returns: A String containing all registered metrics in Prometheus text format
    /// - Note: Use ``resetInternalBuffer()`` to force recalibration
    /// - SeeAlso: ``emitToBuffer()`` for raw UTF-8 bytes, ``emit(into:)`` for custom buffer
    public func emitToString() -> String {
        return bufferBox.withLockedValue { buffer in
            guard buffer.capacity == 0 else {
                // Subsequent times: clear content but keep the capacity
                buffer.removeAll(keepingCapacity: true)
                emit(into: &buffer)
                return String(decoding: buffer, as: UTF8.self)
            }
            // First time: emit and let buffer auto-resize to find the initial optimal size
            emit(into: &buffer)
            return String(decoding: buffer, as: UTF8.self)
        }
    }

    /// Emits all registered metrics in Prometheus text format as a UTF-8 byte array.
    ///
    /// Uses an internal buffer that auto-sizes on first call to find optimal initial capacity. The buffer
    /// may resize during the registry's lifetime if output grows significantly. Subsequent calls reuse the
    /// established capacity, clearing content but preserving the initially allocated memory. Returns a copy.
    ///
    /// - Returns: A copy of the UTF-8 encoded byte array containing all registered metrics
    /// - Note: Use ``resetInternalBuffer()`` to force recalibration
    /// - SeeAlso: ``emitToString()`` for String output, ``emit(into:)`` for custom buffer
    public func emitToBuffer() -> [UInt8] {
        return bufferBox.withLockedValue { buffer in
            guard buffer.capacity == 0 else {
                buffer.removeAll(keepingCapacity: true)
                emit(into: &buffer)
                return Array(buffer)  // Creates a copy
            }
            emit(into: &buffer)
            return Array(buffer)  // Creates a copy
        }
    }

    /// Emits all registered metrics in Prometheus text format into the provided buffer.
    ///
    /// Writes directly into the supplied buffer without any internal buffer management or thread synchronization.
    /// The caller is responsible for buffer sizing, clearing, and thread safety. This method provides maximum
    /// performance and control but requires manual buffer lifecycle management.
    ///
    /// - Parameter buffer: The buffer to write metrics data into. Content will be appended to existing data
    /// - SeeAlso: ``emitToString()`` and ``emitToBuffer()`` for automatic buffer management
    public func emit(into buffer: inout [UInt8]) {
        let metrics = self.box.withLockedValue { $0 }
        let prefixHelp = "HELP"
        let prefixType = "TYPE"

        for (name, metric) in metrics {
            switch metric {
            case .counter(let counterFamily):
                if let help = counterFamily.help, !help.isEmpty {
                    buffer.addLine(prefix: prefixHelp, name: name, value: help)
                }
                buffer.addLine(prefix: prefixType, name: name, value: "counter")
                counterFamily.forEachMetric { counter in
                    counter.emit(into: &buffer)
                }

            case .gauge(let gaugeFamily):
                if let help = gaugeFamily.help, !help.isEmpty {
                    buffer.addLine(prefix: prefixHelp, name: name, value: help)
                }
                buffer.addLine(prefix: prefixType, name: name, value: "gauge")
                gaugeFamily.forEachMetric { gauge in
                    gauge.emit(into: &buffer)
                }

            case .durationHistogram(let histogramFamily):
                if let help = histogramFamily.help, !help.isEmpty {
                    buffer.addLine(prefix: prefixHelp, name: name, value: help)
                }
                buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                histogramFamily.forEachMetric { histogram in
                    histogram.emit(into: &buffer)
                }

            case .valueHistogram(let histogramFamily):
                if let help = histogramFamily.help, !help.isEmpty {
                    buffer.addLine(prefix: prefixHelp, name: name, value: help)
                }
                buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                histogramFamily.forEachMetric { histogram in
                    histogram.emit(into: &buffer)
                }
            }
        }
    }
}

extension [(String, String)] {
    fileprivate var allLabelNames: [String] {
        var result = [String]()
        result.reserveCapacity(self.count)
        for (name, _) in self {
            precondition(!result.contains(name))
            result.append(name)
        }
        result = result.sorted()
        return result
    }

    fileprivate func ensureValidLabelNames() -> [(String, String)] {
        guard self.allSatisfy({ $0.0.isValidLabelName() }) else {
            return self.map { ($0.ensureValidLabelName(), $1) }
        }
        return self
    }
}

extension [UInt8] {
    fileprivate mutating func addLine(prefix: String, name: String, value: String) {
        self.append(contentsOf: #"# "#.utf8)
        self.append(contentsOf: prefix.utf8)
        self.append(contentsOf: #" "#.utf8)
        self.append(contentsOf: name.utf8)
        self.append(contentsOf: #" "#.utf8)
        self.append(contentsOf: value.utf8)
        self.append(contentsOf: #"\#n"#.utf8)
    }
}

protocol PrometheusMetric {
    func emit(into buffer: inout [UInt8])
}

extension PrometheusMetric {
    static func prerenderLabels(_ labels: [(String, String)]) -> [UInt8]? {
        guard !labels.isEmpty else {
            return nil
        }

        var prerendered = [UInt8]()
        for (i, (key, value)) in labels.enumerated() {
            prerendered.append(contentsOf: key.utf8)
            prerendered.append(contentsOf: #"=""#.utf8)
            prerendered.append(contentsOf: value.utf8)
            prerendered.append(UInt8(ascii: #"""#))
            if i < labels.index(before: labels.endIndex) {
                prerendered.append(UInt8(ascii: #","#))
            }
        }
        return prerendered
    }
}

extension String {
    fileprivate func isValidMetricName() -> Bool {
        var isFirstCharacter = true
        for ascii in self.utf8 {
            defer { isFirstCharacter = false }
            switch ascii {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "_"), UInt8(ascii: ":"):
                continue
            case UInt8(ascii: "0"), UInt8(ascii: "9"):
                if isFirstCharacter {
                    return false
                }
                continue
            default:
                return false
            }
        }
        return true
    }

    fileprivate func isValidLabelName() -> Bool {
        var isFirstCharacter = true
        for ascii in self.utf8 {
            defer { isFirstCharacter = false }
            switch ascii {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "_"):
                continue
            case UInt8(ascii: "0"), UInt8(ascii: "9"):
                if isFirstCharacter {
                    return false
                }
                continue
            default:
                return false
            }
        }
        return true
    }

    fileprivate func isDisallowedHelpTextUnicdeScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F,  // C0 Controls
            0x7F...0x9F,  // C1 Controls
            0x2028, 0x2029, 0x200B, 0x200C, 0x200D, 0x2060, 0x00AD,  // Extra security
            0x202A...0x202E,  // BiDi Controls
            0x2066...0x2069:  // Isolate formatting characters
            return true  // Remove
        default:
            return false
        }
    }

    fileprivate func isValidHelpText() -> Bool {
        guard !self.isEmpty else { return true }
        let containsInvalidCharacter = self.unicodeScalars.contains(where: isDisallowedHelpTextUnicdeScalar)
        return !containsInvalidCharacter
    }

    fileprivate func ensureValidMetricName() -> String {
        guard self.isValidMetricName() else {
            var new = self
            new.fixPrometheusName(allowColon: true)
            return new
        }
        return self
    }

    fileprivate func ensureValidLabelName() -> String {
        guard self.isValidLabelName() else {
            var new = self
            new.fixPrometheusName(allowColon: false)
            return new
        }
        return self
    }

    fileprivate func ensureValidHelpText() -> String {
        guard self.isValidHelpText() else {
            var new = self
            new.fixPrometheusHelpText()
            return new
        }
        return self
    }

    fileprivate mutating func fixPrometheusName(allowColon: Bool) {
        var startIndex = self.startIndex
        var isFirstCharacter = true
        while let fixIndex = self[startIndex...].firstIndex(where: { character in
            defer { isFirstCharacter = false }
            switch character {
            case "A"..."Z", "a"..."z", "_":
                return false
            case ":":
                return !allowColon
            case "0"..."9":
                return isFirstCharacter
            default:
                return true
            }
        }) {
            self.replaceSubrange(fixIndex...fixIndex, with: CollectionOfOne("_"))
            startIndex = fixIndex
            if startIndex == self.endIndex {
                break
            }
        }
    }

    fileprivate mutating func fixPrometheusHelpText() {
        var result = self
        result.removeAll { character in
            character.unicodeScalars.contains(where: isDisallowedHelpTextUnicdeScalar)
        }
        self = result
    }
}
