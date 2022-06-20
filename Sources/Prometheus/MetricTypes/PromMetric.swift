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
    /// Prometheus client handling this metric
    var prometheus: PrometheusClient? { get }
}
