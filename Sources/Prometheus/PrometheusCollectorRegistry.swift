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

    private enum Metric {
        case counter(Counter)
        case counterWithLabels([String], [LabelsKey: Counter])
        case gauge(Gauge)
        case gaugeWithLabels([String], [LabelsKey: Gauge])
        case durationHistogram(DurationHistogram)
        case durationHistogramWithLabels([String], [LabelsKey: DurationHistogram], [Duration])
        case valueHistogram(ValueHistogram)
        case valueHistogramWithLabels([String], [LabelsKey: ValueHistogram], [Double])
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
    /// - Returns: A ``Counter`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeCounter(name: String) -> Counter {
        let name = name.ensureValidMetricName()
        return self.box.withLockedValue { store -> Counter in
            guard let value = store[name] else {
                let counter = Counter(name: name, labels: [])
                store[name] = .counter(counter)
                return counter
            }
            guard case .counter(let counter) = value else {
                fatalError(
                    """
                    Could not make Counter with name: \(name), since another metric type
                    already exists for the same name.
                    """
                )
            }

            return counter
        }
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
        return self.makeCounter(name: descriptor.name)
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
        guard !labels.isEmpty else {
            return self.makeCounter(name: name)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()

        return self.box.withLockedValue { store -> Counter in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let counter = Counter(name: name, labels: labels)

                store[name] = .counterWithLabels(labelNames, [LabelsKey(labels): counter])
                return counter
            }
            guard case .counterWithLabels(let labelNames, var dimensionLookup) = value else {
                fatalError(
                    """
                    Could not make Counter with name: \(name) and labels: \(labels), since another
                    metric type already exists for the same name.
                    """
                )
            }

            let key = LabelsKey(labels)
            if let counter = dimensionLookup[key] {
                return counter
            }

            // check if all labels match the already existing ones.
            if labelNames != labels.allLabelNames {
                fatalError(
                    """
                    Could not make Counter with name: \(name) and labels: \(labels), since the
                    label names don't match the label names of previously registered Counters with
                    the same name.
                    """
                )
            }

            let counter = Counter(name: name, labels: labels)
            dimensionLookup[key] = counter
            store[name] = .counterWithLabels(labelNames, dimensionLookup)
            return counter
        }
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
        return self.makeCounter(name: descriptor.name, labels: labels)
    }

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter name: A name to identify ``Gauge``'s value.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(name: String) -> Gauge {
        let name = name.ensureValidMetricName()
        return self.box.withLockedValue { store -> Gauge in
            guard let value = store[name] else {
                let gauge = Gauge(name: name, labels: [])
                store[name] = .gauge(gauge)
                return gauge
            }
            guard case .gauge(let gauge) = value else {
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

    /// Creates a new ``Gauge`` collector or returns the already existing one with the same name,
    /// based on the provided descriptor.
    ///
    /// When the ``PrometheusCollectorRegistry/emit(into:)`` is called, metrics from the
    /// created ``Gauge`` will be part of the export.
    ///
    /// - Parameter descriptor: An ``MetricNameDescriptor`` that provides the fully qualified name for the metric.
    /// - Returns: A ``Gauge`` that is registered with this ``PrometheusCollectorRegistry``
    public func makeGauge(descriptor: MetricNameDescriptor) -> Gauge {
        return self.makeGauge(name: descriptor.name)
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
        guard !labels.isEmpty else {
            return self.makeGauge(name: name)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()

        return self.box.withLockedValue { store -> Gauge in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let gauge = Gauge(name: name, labels: labels)

                store[name] = .gaugeWithLabels(labelNames, [LabelsKey(labels): gauge])
                return gauge
            }
            guard case .gaugeWithLabels(let labelNames, var dimensionLookup) = value else {
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
            store[name] = .gaugeWithLabels(labelNames, dimensionLookup)
            return gauge
        }
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
        return self.makeGauge(name: descriptor.name, labels: labels)
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
        let name = name.ensureValidMetricName()
        return self.box.withLockedValue { store -> DurationHistogram in
            guard let value = store[name] else {
                let gauge = DurationHistogram(name: name, labels: [], buckets: buckets)
                store[name] = .durationHistogram(gauge)
                return gauge
            }
            guard case .durationHistogram(let histogram) = value else {
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
        return self.makeDurationHistogram(name: descriptor.name, buckets: buckets)
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
        guard !labels.isEmpty else {
            return self.makeDurationHistogram(name: name, buckets: buckets)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()

        return self.box.withLockedValue { store -> DurationHistogram in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let histogram = DurationHistogram(name: name, labels: labels, buckets: buckets)

                store[name] = .durationHistogramWithLabels(labelNames, [LabelsKey(labels): histogram], buckets)
                return histogram
            }
            guard case .durationHistogramWithLabels(let labelNames, var dimensionLookup, let storedBuckets) = value
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
            store[name] = .durationHistogramWithLabels(labelNames, dimensionLookup, storedBuckets)
            return histogram
        }
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
        return self.makeDurationHistogram(name: descriptor.name, labels: labels, buckets: buckets)
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
        let name = name.ensureValidMetricName()
        return self.box.withLockedValue { store -> ValueHistogram in
            guard let value = store[name] else {
                let gauge = ValueHistogram(name: name, labels: [], buckets: buckets)
                store[name] = .valueHistogram(gauge)
                return gauge
            }
            guard case .valueHistogram(let histogram) = value else {
                fatalError()
            }

            return histogram
        }
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
        return self.makeValueHistogram(name: descriptor.name, buckets: buckets)
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
    public func makeValueHistogram(name: String, labels: [(String, String)], buckets: [Double]) -> ValueHistogram {
        guard !labels.isEmpty else {
            return self.makeValueHistogram(name: name, buckets: buckets)
        }

        let name = name.ensureValidMetricName()
        let labels = labels.ensureValidLabelNames()

        return self.box.withLockedValue { store -> ValueHistogram in
            guard let value = store[name] else {
                let labelNames = labels.allLabelNames
                let histogram = ValueHistogram(name: name, labels: labels, buckets: buckets)

                store[name] = .valueHistogramWithLabels(labelNames, [LabelsKey(labels): histogram], buckets)
                return histogram
            }
            guard case .valueHistogramWithLabels(let labelNames, var dimensionLookup, let storedBuckets) = value else {
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
            store[name] = .valueHistogramWithLabels(labelNames, dimensionLookup, storedBuckets)
            return histogram
        }
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
        return self.makeValueHistogram(name: descriptor.name, labels: labels, buckets: buckets)
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
            case .counter(let storedCounter):
                guard storedCounter === counter else { return }
                store.removeValue(forKey: counter.name)
            case .counterWithLabels(let labelNames, var dimensions):
                let labelsKey = LabelsKey(counter.labels)
                guard dimensions[labelsKey] === counter else { return }
                dimensions.removeValue(forKey: labelsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: counter.name)
                } else {
                    store[counter.name] = .counterWithLabels(labelNames, dimensions)
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
            case .gauge(let storedGauge):
                guard storedGauge === gauge else { return }
                store.removeValue(forKey: gauge.name)
            case .gaugeWithLabels(let labelNames, var dimensions):
                let dimensionsKey = LabelsKey(gauge.labels)
                guard dimensions[dimensionsKey] === gauge else { return }
                dimensions.removeValue(forKey: dimensionsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: gauge.name)
                } else {
                    store[gauge.name] = .gaugeWithLabels(labelNames, dimensions)
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
            case .durationHistogram(let storedHistogram):
                guard storedHistogram === histogram else { return }
                store.removeValue(forKey: histogram.name)
            case .durationHistogramWithLabels(let labelNames, var dimensions, let buckets):
                let dimensionsKey = LabelsKey(histogram.labels)
                guard dimensions[dimensionsKey] === histogram else { return }
                dimensions.removeValue(forKey: dimensionsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: histogram.name)
                } else {
                    store[histogram.name] = .durationHistogramWithLabels(labelNames, dimensions, buckets)
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
            case .valueHistogram(let storedHistogram):
                guard storedHistogram === histogram else { return }
                store.removeValue(forKey: histogram.name)
            case .valueHistogramWithLabels(let labelNames, var dimensions, let buckets):
                let dimensionsKey = LabelsKey(histogram.labels)
                guard dimensions[dimensionsKey] === histogram else { return }
                dimensions.removeValue(forKey: dimensionsKey)
                if dimensions.isEmpty {
                    store.removeValue(forKey: histogram.name)
                } else {
                    store[histogram.name] = .valueHistogramWithLabels(labelNames, dimensions, buckets)
                }
            default:
                return
            }
        }
    }

    // MARK: Emitting

    public func emit(into buffer: inout [UInt8]) {
        let metrics = self.box.withLockedValue { $0 }

        for (label, metric) in metrics {
            switch metric {
            case .counter(let counter):
                buffer.addTypeLine(label: label, type: "counter")
                counter.emit(into: &buffer)

            case .counterWithLabels(_, let counters):
                buffer.addTypeLine(label: label, type: "counter")
                for counter in counters.values {
                    counter.emit(into: &buffer)
                }

            case .gauge(let gauge):
                buffer.addTypeLine(label: label, type: "gauge")
                gauge.emit(into: &buffer)

            case .gaugeWithLabels(_, let gauges):
                buffer.addTypeLine(label: label, type: "gauge")
                for gauge in gauges.values {
                    gauge.emit(into: &buffer)
                }

            case .durationHistogram(let histogram):
                buffer.addTypeLine(label: label, type: "histogram")
                histogram.emit(into: &buffer)

            case .durationHistogramWithLabels(_, let histograms, _):
                buffer.addTypeLine(label: label, type: "histogram")
                for histogram in histograms.values {
                    histogram.emit(into: &buffer)
                }

            case .valueHistogram(let histogram):
                buffer.addTypeLine(label: label, type: "histogram")
                histogram.emit(into: &buffer)

            case .valueHistogramWithLabels(_, let histograms, _):
                buffer.addTypeLine(label: label, type: "histogram")
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
    fileprivate mutating func addTypeLine(label: String, type: String) {
        self.append(contentsOf: #"# TYPE "#.utf8)
        self.append(contentsOf: label.utf8)
        self.append(contentsOf: #" "#.utf8)
        self.append(contentsOf: type.utf8)
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
}
