public protocol Metric {
    var name: String { get }
    var help: String? { get }
    
    func getMetric() -> String
}

public protocol MetricLabels: Codable, Hashable {
    init()
}
