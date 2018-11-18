public class Info<Labels: MetricLabels>: Metric, PrometheusHandled {
    internal let prometheus: Prometheus
    
    public let name: String
    public let help: String?
    
    public let _type: MetricType = .info
    
    internal var labels = Labels()
    
    internal init(_ name: String, _ help: String? = nil, _ p: Prometheus) {
        self.name = name
        self.help = help
        self.prometheus = p
    }
    
    public func info(_ labels: Labels) {
        self.labels = labels
    }
    
    public func getMetric() -> String {
        var output = [String]()
        
        output.append(headers)
        
        let labelsString = encodeLabels(labels)
        output.append("\(name)\(labelsString) 1.0")
        
        return output.joined(separator: "\n")
    }
}
