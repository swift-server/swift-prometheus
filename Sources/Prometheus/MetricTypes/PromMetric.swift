import NIO

/// Different types of metrics supported by SwiftPrometheus
public enum PromMetricType: String {
    /// See `PromCounter`
    case counter
    /// See `PromGauge`
    case gauge
    /// See `PromHistogram`
    case histogram
    /// See `PromSummary`
    case summary
}

public enum Prometheus {
    /// Default capacity of Summaries
    public static let defaultSummaryCapacity = 500

    /// Default quantiles used by Summaries
    public static let defaultQuantiles = [0.01, 0.05, 0.5, 0.9, 0.95, 0.99, 0.999]
}

/// Metric protocol
///
/// See https://prometheus.io/docs/concepts/metric_types/
public protocol PromMetric {
    /// Name of the metric
    var name: String { get }
    /// Optional help of the metric
    var help: String? { get }
    /// Type of the metric
    var _type: PromMetricType { get }
    
    /// Retrieves the Prometheus-formatted metric data
    func collect() -> String
}

extension PromMetric {
    /// Helper method to record metrics into a `ByteBuffer` directly
    ///
    /// - Parameters:
    ///     - buffer: `ByteBuffer` to collect into
    func collect(into buffer: inout ByteBuffer) {
        buffer.writeString(collect())
    }
}

/// Adding a prometheus instance to all metrics
internal protocol PrometheusHandled {
    /// Promtheus client handling this metric
    var prometheus: PrometheusClient? { get }
}

/// Base MetricLabels protocol
///
/// MetricLabels are used to enrich & specify metrics.
///
///     struct Labels: MetricLabels {
///         let status: String = "unknown"
///     }
///     let counter = myProm.createCounter(...)
///     counter.inc(12, labels: Labels(status: "failure")
///     counter.inc(1, labels: Labels(status: "success")
/// Will result in the following Prometheus output:
///
///     # TYPE my_counter counter
///     my_counter 0
///     my_counter{status="unknown"} 0
///     my_counter{status="failure"} 12
///     my_counter{status="success"} 1
public protocol MetricLabels: Encodable, Hashable {
    /// Create empty labels
    init()
}
