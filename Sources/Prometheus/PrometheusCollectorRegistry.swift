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

    private struct CounterWithHelp {
        var counter: Counter
        let help: String
    }

    private struct CounterGroup {
        // A collection of Counter metrics, each with a unique label set, that share the same metric name.
        // Distinct help strings for the same metric name are permitted, but Prometheus retains only the
        // most recent one. For an unlabelled Counter, the empty label set is used as the key, and the
        // collection contains only one entry. Finally, for clarification, the same Counter metric name can
        // simultaneously be labeled and unlabeled.
        var countersByLabelSets: [LabelsKey: CounterWithHelp]
    }

    private enum Metric {
        case counter(CounterGroup)
        case gauge(Gauge, help: String)
        case gaugeWithLabels([String], [LabelsKey: Gauge], help: String)
        case durationHistogram(DurationHistogram, help: String)
        case durationHistogramWithLabels([String], [LabelsKey: DurationHistogram], [Duration], help: String)
        case valueHistogram(ValueHistogram, help: String)
        case valueHistogramWithLabels([String], [LabelsKey: ValueHistogram], [Double], help: String)
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
                let counterWithHelp = CounterWithHelp(counter: counter, help: help)
                let counterGroup = CounterGroup(
                    countersByLabelSets: [key: counterWithHelp]
                )
                store[name] = .counter(counterGroup)
                return counter
            }
            switch entry {
            case .counter(var existingCounterGroup):
                if let existingCounterWithHelp = existingCounterGroup.countersByLabelSets[key] {
                    return existingCounterWithHelp.counter
                }

                // Even if the metric name is identical, each label set defines a unique time series.
                let counter = Counter(name: name, labels: labels)
                let counterWithHelp = CounterWithHelp(counter: counter, help: help)
                existingCounterGroup.countersByLabelSets[key] = counterWithHelp

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
        let name = name.ensureValidMetricName()
        let help = help.ensureValidHelpText()
        return self.box.withLockedValue { store -> Gauge in
            guard let value = store[name] else {
                let gauge = Gauge(name: name, labels: [])
                store[name] = .gauge(gauge, help: help)
                return gauge
            }
            guard case .gauge(let gauge, _) = value else {
                fatalError(
                    """
                    Could not make Gauge with name: \(name), since another metric type already
                    exists for the same name.
                    """
                )
            }

            return gauge
        }
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(name: String) -> Gauge {
        return self.makeGauge(name: name, help: "")
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
        return self.makeGauge(name: descriptor.name, help: descriptor.helpText ?? "")
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
        guard !labels.isEmpty else {
            return self.makeGauge(name: name, help: help)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()

        return self.box.withLockedValue { store -> Gauge in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let gauge = Gauge(name: name, labels: labels)

                store[name] = .gaugeWithLabels(labelNames, [LabelsKey(labels): gauge], help: help)
                return gauge
            }
            guard case .gaugeWithLabels(let labelNames, var dimensionLookup, let help) = value else {
                fatalError(
                    """
                    Could not make Gauge with name: \(name) and labels: \(labels), since another
                    metric type already exists for the same name.
                    """
                )
            }

            let key = LabelsKey(labels)
            if let gauge = dimensionLookup[key] {
                return gauge
            }

            // check if all labels match the already existing ones.
            if labelNames != labels.allLabelNames {
                fatalError(
                    """
                    Could not make Gauge with name: \(name) and labels: \(labels), since the
                    label names don't match the label names of previously registered Gauges with
                    the same name.
                    """
                )
            }

            let gauge = Gauge(name: name, labels: labels)
            dimensionLookup[key] = gauge
            store[name] = .gaugeWithLabels(labelNames, dimensionLookup, help: help)
            return gauge
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
        let name = name.ensureValidMetricName()
        let help = help.ensureValidHelpText()
        return self.box.withLockedValue { store -> DurationHistogram in
            guard let value = store[name] else {
                let gauge = DurationHistogram(name: name, labels: [], buckets: buckets)
                store[name] = .durationHistogram(gauge, help: help)
                return gauge
            }
            guard case .durationHistogram(let histogram, _) = value else {
                fatalError(
                    """
                    Could not make DurationHistogram with name: \(name), since another
                    metric type already exists for the same name.
                    """
                )
            }

            return histogram
        }
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
        return self.makeDurationHistogram(name: name, buckets: buckets, help: "")
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
        return self.makeDurationHistogram(name: descriptor.name, buckets: buckets, help: descriptor.helpText ?? "")
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
        guard !labels.isEmpty else {
            return self.makeDurationHistogram(name: name, buckets: buckets, help: help)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()

        return self.box.withLockedValue { store -> DurationHistogram in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let histogram = DurationHistogram(name: name, labels: labels, buckets: buckets)

                store[name] = .durationHistogramWithLabels(
                    labelNames,
                    [LabelsKey(labels): histogram],
                    buckets,
                    help: help
                )
                return histogram
            }
            guard
                case .durationHistogramWithLabels(let labelNames, var dimensionLookup, let storedBuckets, let help) =
                    value
            else {
                fatalError(
                    """
                    Could not make DurationHistogram with name: \(name) and labels: \(labels), since another
                    metric type already exists for the same name.
                    """
                )
            }

            let key = LabelsKey(labels)
            if let histogram = dimensionLookup[key] {
                return histogram
            }

            // check if all labels match the already existing ones.
            if labelNames != labels.allLabelNames {
                fatalError(
                    """
                    Could not make DurationHistogram with name: \(name) and labels: \(labels), since the
                    label names don't match the label names of previously registered Gauges with
                    the same name.
                    """
                )
            }
            if storedBuckets != buckets {
                fatalError(
                    """
                    Could not make DurationHistogram with name: \(name) and labels: \(labels), since the
                    buckets don't match the buckets of previously registered TimeHistograms with
                    the same name.
                    """
                )
            }

            precondition(storedBuckets == buckets)

            let histogram = DurationHistogram(name: name, labels: labels, buckets: storedBuckets)
            dimensionLookup[key] = histogram
            store[name] = .durationHistogramWithLabels(labelNames, dimensionLookup, storedBuckets, help: help)
            return histogram
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
        let name = name.ensureValidMetricName()
        let help = help.ensureValidHelpText()
        return self.box.withLockedValue { store -> ValueHistogram in
            guard let value = store[name] else {
                let gauge = ValueHistogram(name: name, labels: [], buckets: buckets)
                store[name] = .valueHistogram(gauge, help: help)
                return gauge
            }
            guard case .valueHistogram(let histogram, _) = value else {
                fatalError()
            }

            return histogram
        }
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
        return self.makeValueHistogram(name: name, buckets: buckets, help: "")
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
        return self.makeValueHistogram(name: descriptor.name, buckets: buckets, help: descriptor.helpText ?? "")
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
        guard !labels.isEmpty else {
            return self.makeValueHistogram(name: name, buckets: buckets, help: help)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()
        let help = help.ensureValidHelpText()

        return self.box.withLockedValue { store -> ValueHistogram in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let histogram = ValueHistogram(name: name, labels: labels, buckets: buckets)

                store[name] = .valueHistogramWithLabels(labelNames, [LabelsKey(labels): histogram], buckets, help: help)
                return histogram
            }
            guard
                case .valueHistogramWithLabels(let labelNames, var dimensionLookup, let storedBuckets, let help) = value
            else {
                fatalError()
            }

            let key = LabelsKey(labels)
            if let histogram = dimensionLookup[key] {
                return histogram
            }

            // check if all labels match the already existing ones.
            precondition(labelNames == labels.allLabelNames)
            precondition(storedBuckets == buckets)

            let histogram = ValueHistogram(name: name, labels: labels, buckets: storedBuckets)
            dimensionLookup[key] = histogram
            store[name] = .valueHistogramWithLabels(labelNames, dimensionLookup, storedBuckets, help: help)
            return histogram
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
                guard let existingCounterGroup = counterGroup.countersByLabelSets[key],
                    existingCounterGroup.counter === counter
                else {
                    return
                }
                counterGroup.countersByLabelSets.removeValue(forKey: key)

                if counterGroup.countersByLabelSets.isEmpty {
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
            case .gauge(let storedGauge, _):
                guard storedGauge === gauge else { return }
                store.removeValue(forKey: gauge.name)
            case .gaugeWithLabels(let labelNames, var dimensions, let help):
                let dimensionsKey = LabelsKey(gauge.labels)
                guard dimensions[dimensionsKey] === gauge else { return }
                dimensions.removeValue(forKey: dimensionsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: gauge.name)
                } else {
                    store[gauge.name] = .gaugeWithLabels(labelNames, dimensions, help: help)
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
            case .durationHistogram(let storedHistogram, _):
                guard storedHistogram === histogram else { return }
                store.removeValue(forKey: histogram.name)
            case .durationHistogramWithLabels(let labelNames, var dimensions, let buckets, let help):
                let dimensionsKey = LabelsKey(histogram.labels)
                guard dimensions[dimensionsKey] === histogram else { return }
                dimensions.removeValue(forKey: dimensionsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: histogram.name)
                } else {
                    store[histogram.name] = .durationHistogramWithLabels(labelNames, dimensions, buckets, help: help)
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
            case .valueHistogram(let storedHistogram, _):
                guard storedHistogram === histogram else { return }
                store.removeValue(forKey: histogram.name)
            case .valueHistogramWithLabels(let labelNames, var dimensions, let buckets, let help):
                let dimensionsKey = LabelsKey(histogram.labels)
                guard dimensions[dimensionsKey] === histogram else { return }
                dimensions.removeValue(forKey: dimensionsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: histogram.name)
                } else {
                    store[histogram.name] = .valueHistogramWithLabels(labelNames, dimensions, buckets, help: help)
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
                guard let _ = counterGroup.countersByLabelSets.first?.value else {
                    continue
                }
                for counterWithHelp in counterGroup.countersByLabelSets.values {
                    let help = counterWithHelp.help
                    help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                    buffer.addLine(prefix: prefixType, name: name, value: "counter")
                    counterWithHelp.counter.emit(into: &buffer)
                }

            case .gauge(let gauge, let help):
                help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                buffer.addLine(prefix: prefixType, name: name, value: "gauge")
                gauge.emit(into: &buffer)

            case .gaugeWithLabels(_, let gauges, let help):
                help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                buffer.addLine(prefix: prefixType, name: name, value: "gauge")
                for gauge in gauges.values {
                    gauge.emit(into: &buffer)
                }

            case .durationHistogram(let histogram, let help):
                help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                histogram.emit(into: &buffer)

            case .durationHistogramWithLabels(_, let histograms, _, let help):
                help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                for histogram in histograms.values {
                    histogram.emit(into: &buffer)
                }

            case .valueHistogram(let histogram, let help):
                help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                histogram.emit(into: &buffer)

            case .valueHistogramWithLabels(_, let histograms, _, let help):
                help.isEmpty ? () : buffer.addLine(prefix: prefixHelp, name: name, value: help)
                buffer.addLine(prefix: prefixType, name: name, value: "histogram")
                for histogram in histograms.values {
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
