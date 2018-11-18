public protocol Metric {
    var name: String { get }
    var help: String? { get }
    
    func getMetric() -> String
}

internal protocol PrometheusHandled {
    var prometheus: Prometheus { get }
}

public protocol MetricLabels: Codable, Hashable {
    init()
}
