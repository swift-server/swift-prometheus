public class Gauge<NumType: Numeric, Labels: MetricLabels>: Metric, PrometheusHandled {
    internal let prometheus: Prometheus
    
    public let name: String
    public let help: String?
    
    public let _type: MetricType = .gauge
    
    private var value: NumType

    private var initialValue: NumType
    
    private var metrics: [Labels: NumType] = [:]
    
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

        output.append("\(name) \(value)")
        
        metrics.forEach { (labels, value) in
            let labelsString = encodeLabels(labels)
            output.append("\(name)\(labelsString) \(value)")
        }
        
        return output.joined(separator: "\n")
    }
    
    @discardableResult
    public func set(_ amount: NumType, _ labels: Labels? = nil) -> NumType {
        if let labels = labels {
            self.metrics[labels] = amount
            return amount
        } else {
            self.value = amount
            return self.value
        }
    }
    
    @discardableResult
    public func inc(_ amount: NumType, _ labels: Labels? = nil) -> NumType {
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
    
    @discardableResult
    public func inc(_ labels: Labels? = nil) -> NumType {
        return self.inc(1, labels)
    }

    @discardableResult
    public func dec(_ amount: NumType, _ labels: Labels? = nil) -> NumType {
        if let labels = labels {
            var val = self.metrics[labels] ?? initialValue
            val -= amount
            self.metrics[labels] = val
            return val
        } else {
            self.value -= amount
            return self.value
        }
    }
    
    @discardableResult
    public func dec(_ labels: Labels? = nil) -> NumType {
        return self.dec(1, labels)
    }

    public func get(_ labels: Labels? = nil) -> NumType {
        if let labels = labels {
            return self.metrics[labels] ?? initialValue
        } else {
            return self.value
        }
    }
}
