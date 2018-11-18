public enum MetricType: String {
    case counter, gauge, histogram, summary, info, `enum`
}

public protocol Metric {
    var name: String { get }
    var help: String? { get }
    var _type: MetricType { get }
    
    func getMetric() -> String
}

extension Metric {
    var headers: String {
        var output = [String]()
        if let help = help {
            output.append("# HELP \(name) \(help)")
        }
        output.append("# TYPE \(name) \(_type)")
        return output.joined(separator: "\n")
    }
}

internal protocol PrometheusHandled {
    var prometheus: Prometheus { get }
}

public protocol MetricLabels: Codable, Hashable {
    init()
}
