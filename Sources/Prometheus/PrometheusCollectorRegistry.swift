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

    private struct MetricWithHelp<Metric: AnyObject & Sendable>: Sendable {
        var metric: Metric
        let help: String
    }

    private enum HistogramBuckets: Sendable, Hashable {
        case duration([Duration])
        case value([Double])
    }

    /// A collection of metrics, each with a unique label set, that share the same metric name.
    /// Distinct help strings for the same metric name are permitted, but Prometheus retains only the
    /// first one. For an unlabelled metric, the empty label set is used as the key, and the
    /// collection contains only one entry. Finally, for clarification, the same metric name can
    /// simultaneously be labeled and unlabeled.
    /// For histograms, the buckets are immutable for a MetricGroup once initialized with the first
    /// metric. See also https://github.com/prometheus/OpenMetrics/issues/197.
    private struct MetricGroup<Metric: Sendable & AnyObject>: Sendable {
        var metricsByLabelSets: [LabelsKey: MetricWithHelp<Metric>]
        let buckets: HistogramBuckets?

        init(metricsByLabelSets: [LabelsKey: MetricWithHelp<Metric>] = [:], buckets: HistogramBuckets? = nil) {
            self.metricsByLabelSets = metricsByLabelSets
            self.buckets = buckets
        }
    }

    private enum Metric {
        case counter(MetricGroup<Counter>)
        case gauge(MetricGroup<Gauge>)
        case durationHistogram(MetricGroup<DurationHistogram>)
        case valueHistogram(MetricGroup<ValueHistogram>)
    }

    private let box = NIOLockedValueBox([String: Metric]())

    /// Create a new collector registry
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
    public func makeCounter(name: String, help: String) -> Counter {
        return self.makeCounter(name: name, labels: [], help: help)
    }

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Counter``'s value.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeCounter(name: String) -> Counter {
        return self.makeCounter(name: name, labels: [], help: "")
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
        return self.makeCounter(name: descriptor.name, labels: [], help: descriptor.helpText ?? "")
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
    public func makeCounter(name: String, labels: [(String, String)], help: String) -> Counter {
        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()
        let key = LabelsKey(labels)

        return self.box.withLockedValue { store -> Counter in
            guard let entry = store[name] else {
                // First time a Counter is registered with this name.
                let counter = Counter(name: name, labels: labels)
                let counterWithHelp = MetricWithHelp(metric: counter, help: help)
                let counterGroup = MetricGroup(
                    metricsByLabelSets: [key: counterWithHelp]
                )
                store[name] = .counter(counterGroup)
                return counter
            }
            switch entry {
            case .counter(var existingCounterGroup):
                if let existingCounterWithHelp = existingCounterGroup.metricsByLabelSets[key] {
                    return existingCounterWithHelp.metric
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let counter = Counter(name: name, labels: labels)
                let counterWithHelp = MetricWithHelp(metric: counter, help: help)
                existingCounterGroup.metricsByLabelSets[key] = counterWithHelp

                // Write the modified entry back to the store.
                store[name] = .counter(existingCounterGroup)

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

    /// Creates a new ``Counter`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Counter`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Counter``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeCounter(name: String, labels: [(String, String)]) -> Counter {
        return self.makeCounter(name: name, labels: labels, help: "")
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
        return self.makeCounter(name: descriptor.name, labels: labels, help: descriptor.helpText ?? "")
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
    public func makeGauge(name: String, help: String) -> Gauge {
        return self.makeGauge(name: name, labels: [], help: help)
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(name: String) -> Gauge {
        return self.makeGauge(name: name, labels: [], help: "")
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
        return self.makeGauge(name: descriptor.name, labels: [], help: descriptor.helpText ?? "")
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
    public func makeGauge(name: String, labels: [(String, String)], help: String) -> Gauge {
        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()
        let key = LabelsKey(labels)

        return self.box.withLockedValue { store -> Gauge in
            guard let entry = store[name] else {
                // First time a Gauge is registered with this name.
                let gauge = Gauge(name: name, labels: labels)
                let gaugeWithHelp = MetricWithHelp(metric: gauge, help: help)
                let gaugeGroup = MetricGroup(
                    metricsByLabelSets: [key: gaugeWithHelp]
                )
                store[name] = .gauge(gaugeGroup)
                return gauge
            }
            switch entry {
            case .gauge(var existingGaugeGroup):
                if let existingGaugeWithHelp = existingGaugeGroup.metricsByLabelSets[key] {
                    return existingGaugeWithHelp.metric
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let gauge = Gauge(name: name, labels: labels)
                let gaugeWithHelp = MetricWithHelp(metric: gauge, help: help)
                existingGaugeGroup.metricsByLabelSets[key] = gaugeWithHelp

                // Write the modified entry back to the store.
                store[name] = .gauge(existingGaugeGroup)

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

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Parameter labels: Labels are sets of key-value pairs that allow us to characterize and organize
    ///                     what’s actually being measured in a Prometheus metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(name: String, labels: [(String, String)]) -> Gauge {
        return self.makeGauge(name: name, labels: labels, help: "")
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
        return self.makeGauge(name: descriptor.name, labels: labels, help: descriptor.helpText ?? "")
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
    public func makeDurationHistogram(name: String, buckets: [Duration], help: String) -> DurationHistogram {
        return self.makeDurationHistogram(name: name, labels: [], buckets: buckets, help: help)
    }

    /// Creates a new ``DurationHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``DurationHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``DurationHistogram``'s value.
    /// - Parameter buckets: Define the buckets that shall be used within the ``DurationHistogram``
    /// - Returns: A ``DurationHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeDurationHistogram(name: String, buckets: [Duration]) -> DurationHistogram {
        return self.makeDurationHistogram(name: name, labels: [], buckets: buckets, help: "")
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
        return self.makeDurationHistogram(
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
    public func makeDurationHistogram(
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
                let histogramWithHelp = MetricWithHelp(metric: histogram, help: help)
                let histogramGroup = MetricGroup(
                    metricsByLabelSets: [key: histogramWithHelp],
                    buckets: .duration(buckets)
                )
                store[name] = .durationHistogram(histogramGroup)
                return histogram
            }

            switch entry {
            case .durationHistogram(var existingHistogramGroup):
                // Validate buckets match the stored ones.
                if case .duration(let storedBuckets) = existingHistogramGroup.buckets {
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

                if let existingHistogramWithHelp = existingHistogramGroup.metricsByLabelSets[key] {
                    return existingHistogramWithHelp.metric
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let histogram = DurationHistogram(name: name, labels: labels, buckets: buckets)
                let histogramWithHelp = MetricWithHelp(metric: histogram, help: help)
                existingHistogramGroup.metricsByLabelSets[key] = histogramWithHelp

                // Write the modified entry back to the store.
                store[name] = .durationHistogram(existingHistogramGroup)

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
    public func makeDurationHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Duration]
    ) -> DurationHistogram {
        return self.makeDurationHistogram(
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
        return self.makeDurationHistogram(
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
    public func makeValueHistogram(name: String, buckets: [Double], help: String) -> ValueHistogram {
        return self.makeValueHistogram(name: name, labels: [], buckets: buckets, help: help)
    }

    /// Creates a new ``ValueHistogram`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``ValueHistogram`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``ValueHistogram``'s value.
    /// - Parameter buckets: Define the buckets that shall be used within the ``ValueHistogram``
    /// - Returns: A ``ValueHistogram`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeValueHistogram(name: String, buckets: [Double]) -> ValueHistogram {
        return self.makeValueHistogram(name: name, labels: [], buckets: buckets, help: "")
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
        return self.makeValueHistogram(
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
    public func makeValueHistogram(
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
                let histogramWithHelp = MetricWithHelp(metric: histogram, help: help)
                let histogramGroup = MetricGroup(
                    metricsByLabelSets: [key: histogramWithHelp],
                    buckets: .value(buckets)
                )
                store[name] = .valueHistogram(histogramGroup)
                return histogram
            }

            switch entry {
            case .valueHistogram(var existingHistogramGroup):
                // Validate buckets match the stored ones.
                if case .value(let storedBuckets) = existingHistogramGroup.buckets {
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

                if let existingHistogramWithHelp = existingHistogramGroup.metricsByLabelSets[key] {
                    return existingHistogramWithHelp.metric
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let histogram = ValueHistogram(name: name, labels: labels, buckets: buckets)
                let histogramWithHelp = MetricWithHelp(metric: histogram, help: help)
                existingHistogramGroup.metricsByLabelSets[key] = histogramWithHelp

                // Write the modified entry back to the store.
                store[name] = .valueHistogram(existingHistogramGroup)

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
    public func makeValueHistogram(
        name: String,
        labels: [(String, String)],
        buckets: [Double]
    ) -> ValueHistogram {
        return self.makeValueHistogram(
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
        return self.makeValueHistogram(
            name: descriptor.name,
            labels: labels,
            buckets: buckets,
            help: descriptor.helpText ?? ""
        )
    }

    // MARK: - Histogram

    // MARK: Destroying Metrics

    /// Unregisters a ``Counter`` from the ``PrometheusCollectorRegistry``. This means that the provided ``Counter``
    /// will not be included in future ``emit(into:)`` calls.
    ///
    /// - Note: If the provided ``Counter`` is unknown to the registry this function call will be ignored
    /// - Parameter counter: The ``Counter`` that shall be removed from the registry
    public func unregisterCounter(_ counter: Counter) {
        self.box.withLockedValue { store in
            switch store[counter.name] {
            case .counter(var counterGroup):
                let key = LabelsKey(counter.labels)
                guard let existingCounterGroup = counterGroup.metricsByLabelSets[key],
                    existingCounterGroup.metric === counter
                else {
                    return
                }
                counterGroup.metricsByLabelSets.removeValue(forKey: key)

                if counterGroup.metricsByLabelSets.isEmpty {
                    store.removeValue(forKey: counter.name)
                } else {
                    store[counter.name] = .counter(counterGroup)
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
            case .gauge(var gaugeGroup):
                let key = LabelsKey(gauge.labels)
                guard let existingGaugeGroup = gaugeGroup.metricsByLabelSets[key],
                    existingGaugeGroup.metric === gauge
                else {
                    return
                }
                gaugeGroup.metricsByLabelSets.removeValue(forKey: key)

                if gaugeGroup.metricsByLabelSets.isEmpty {
                    store.removeValue(forKey: gauge.name)
                } else {
                    store[gauge.name] = .gauge(gaugeGroup)
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
            case .durationHistogram(var histogramGroup):
                let key = LabelsKey(histogram.labels)
                guard let existingHistogramGroup = histogramGroup.metricsByLabelSets[key],
                    existingHistogramGroup.metric === histogram
                else {
                    return
                }
                histogramGroup.metricsByLabelSets.removeValue(forKey: key)

                if histogramGroup.metricsByLabelSets.isEmpty {
                    store.removeValue(forKey: histogram.name)
                } else {
                    store[histogram.name] = .durationHistogram(histogramGroup)
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
            case .valueHistogram(var histogramGroup):
                let key = LabelsKey(histogram.labels)
                guard let existingHistogramGroup = histogramGroup.metricsByLabelSets[key],
                    existingHistogramGroup.metric === histogram
                else {
                    return
                }
                histogramGroup.metricsByLabelSets.removeValue(forKey: key)

                if histogramGroup.metricsByLabelSets.isEmpty {
                    store.removeValue(forKey: histogram.name)
                } else {
                    store[histogram.name] = .valueHistogram(histogramGroup)
                }
            default:
                return
            }
        }
    }

    // MARK: Emitting

    public func emit(into buffer: inout [UInt8]) {
        let metrics = self.box.withLockedValue { $0 }
        let prefixHelp = "HELP"
        let prefixType = "TYPE"

        for (name, metric) in metrics {
            switch metric {
            case .counter(let counterGroup):
                // Should not be empty, as a safeguard skip if it is.
                guard let _ = counterGroup.metricsByLabelSets.first?.value else {
                    continue
                }
                for counterWithHelp in counterGroup.metricsByLabelSets.values {
                    let help = counterWithHelp.help
                    help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                    buffer.addLine(prefix: prefixType, name: name, value: "counter")
                    counterWithHelp.metric.emit(into: &buffer)
                }

            case .gauge(let gaugeGroup):
                // Should not be empty, as a safeguard skip if it is.
                guard let _ = gaugeGroup.metricsByLabelSets.first?.value else {
                    continue
                }
                for gaugeWithHelp in gaugeGroup.metricsByLabelSets.values {
                    let help = gaugeWithHelp.help
                    help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                    buffer.addLine(prefix: prefixType, name: name, value: "gauge")
                    gaugeWithHelp.metric.emit(into: &buffer)
                }

            case .durationHistogram(let histogramGroup):
                // Should not be empty, as a safeguard skip if it is.
                guard let _ = histogramGroup.metricsByLabelSets.first?.value else {
                    continue
                }
                for histogramWithHelp in histogramGroup.metricsByLabelSets.values {
                    let help = histogramWithHelp.help
                    help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                    buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                    histogramWithHelp.metric.emit(into: &buffer)
                }

            case .valueHistogram(let histogramGroup):
                // Should not be empty, as a safeguard skip if it is.
                guard let _ = histogramGroup.metricsByLabelSets.first?.value else {
                    continue
                }
                for histogramWithHelp in histogramGroup.metricsByLabelSets.values {
                    let help = histogramWithHelp.help
                    help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                    buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                    histogramWithHelp.metric.emit(into: &buffer)
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
