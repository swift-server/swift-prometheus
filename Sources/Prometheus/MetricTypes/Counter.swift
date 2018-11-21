public class Counter<NumType: Numeric, Labels: MetricLabels>: Metric, PrometheusHandled {
    internal let prometheus: Prometheus
    
    public let name: String
    public let help: String?
    
    public let _type: MetricType = .counter
    
    internal var value: NumType

    private var initialValue: NumType

    internal var metrics: [Labels: NumType] = [:]
    
    internal init(_ name: String, _ help: String? = nil, _ initialValue: NumType = 0, _ p: Prometheus) {
        self.name = name
        self.help = help
        self.initialValue = initialValue
        self.value = initialValue
        self.prometheus = p
    }
    
    public func getMetric() -> String {
        var output = [String]()
        
        output.append(headers)
        
        if value != initialValue && initialValue == 0 {
            output.append("\(name) \(value)")
        }

        metrics.forEach { (labels, value) in
            let labelsString = encodeLabels(labels)
            output.append("\(name)\(labelsString) \(value)")
        }
        
        return output.joined(separator: "\n")
    }
    
    @discardableResult
    public func inc(_ amount: NumType = 1, _ labels: Labels? = nil) -> NumType {
        if let labels = labels {
            var val = self.metrics[labels] ?? initialValue
            val += amount
            self.metrics[labels] = val
            return val
        } else {
            self.value += amount
            return self.value
        }
    }
    
    public func get(_ labels: Labels? = nil) -> NumType {
        if let labels = labels {
            return self.metrics[labels] ?? initialValue
        } else {
            return self.value
        }
    }
}

