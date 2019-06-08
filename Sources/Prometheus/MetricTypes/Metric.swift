/// Different types of metrics supported by SwiftPrometheus
public enum MetricType: String {
    case counter, gauge, histogram, summary, info
}

/// Metric protocol
///
/// See https://prometheus.io/docs/concepts/metric_types/
public protocol Metric {
    var name: String { get }
    var help: String? { get }
    var _type: MetricType { get }
    
    func getMetric() -> String
}

//extension Metric {
//    /// Default headers for a metric
//    var headers: String {
//        var output = [String]()
//        return output.joined(separator: "\n")
//    }
//}

/// Adding a prometheus instance to all
/// metrics
internal protocol PrometheusHandled {
    var prometheus: PrometheusClient { get }
}

/// Base MetricLabels protocol
public protocol MetricLabels: Codable, Hashable {
    init()
}
