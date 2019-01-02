/// Prometheus Counter metric
///
/// See https://prometheus.io/docs/concepts/metric_types/#gauge
public class Gauge<NumType: Numeric, Labels: MetricLabels>: Metric, PrometheusHandled {
    /// Prometheus instance that created this Gauge
    internal let prometheus: PrometheusClient
    
    /// Name of the Gauge, required
    public let name: String
    /// Help text of the Gauge, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: MetricType = .gauge
    
    /// Current value of the counter
    private var value: NumType
    
    /// Initial value of the Gauge
    private var initialValue: NumType
    
    /// Storage of values that have labels attached
    private var metrics: [Labels: NumType] = [:]
    
    /// Creates a new instance of a Gauge
    ///
    /// - Parameters:
    ///     - name: Name of the Gauge
    ///     - help: Helpt text of the Gauge
    ///     - initialValue: Initial value to set the Gauge to
    ///     - p: Prometheus instance that created this Gauge
    internal init(_ name: String, _ help: String? = nil, _ initialValue: NumType = 0, _ p: PrometheusClient) {
        self.name = name
        self.help = help
        self.initialValue = initialValue
        self.value = initialValue
        self.prometheus = p
    }
    
    /// Gets the metric string for this Gauge
    ///
    /// - Returns:
    ///     Newline seperated Prometheus formatted metric string
    public func getMetric(_ done: @escaping (String) -> Void) {
        prometheusQueue.async(flags: .barrier) {
            var output = [String]()
            
            if let help = self.help {
                output.append("# HELP \(self.name) \(help)")
            }
            output.append("# TYPE \(self.name) \(self._type)")

            output.append("\(self.name) \(self.value)")
            
            self.metrics.forEach { (labels, value) in
                let labelsString = encodeLabels(labels)
                output.append("\(self.name)\(labelsString) \(value)")
            }
            
            done(output.joined(separator: "\n"))
        }
    }
    
    /// Sets the Gauge
    ///
    /// - Parameters:
    ///     - amount: Amount to set the gauge to
    ///     - labels: Labels to attach to the value
    ///
    public func set(_ amount: NumType, _ labels: Labels? = nil, _ done: @escaping (NumType) -> Void = { _ in }) {
        prometheusQueue.async(flags: .barrier) {
        if let labels = labels {
            self.metrics[labels] = amount
            done(amount)
        } else {
            self.value = amount
            done(self.value)
        }
        }
    }
    
    /// Increments the Gauge
    ///
    /// - Parameters:
    ///     - amount: Amount to increment the Gauge with
    ///     - labels: Labels to attach to the value
    ///
    public func inc(_ amount: NumType, _ labels: Labels? = nil, _ done: @escaping (NumType) -> Void = { _ in }) {
        prometheusQueue.async(flags: .barrier) {
        if let labels = labels {
            var val = self.metrics[labels] ?? self.initialValue
            val += amount
            self.metrics[labels] = val
            done(val)
        } else {
            self.value += amount
            done(self.value)
        }
        }
    }
    
    /// Increments the Gauge
    ///
    /// - Parameters:
    ///     - labels: Labels to attach to the value
    ///
    public func inc(_ labels: Labels? = nil, _ done: @escaping (NumType) -> Void = { _ in }) {
        self.inc(1, labels) {
            done($0)
        }
    }
    
    /// Decrements the Gauge
    ///
    /// - Parameters:
    ///     - amount: Amount to decrement the Gauge with
    ///     - labels: Labels to attach to the value
    ///
    public func dec(_ amount: NumType, _ labels: Labels? = nil, _ done: @escaping (NumType) -> Void = { _ in }) {
        prometheusQueue.async(flags: .barrier) {
        if let labels = labels {
            var val = self.metrics[labels] ?? self.initialValue
            val -= amount
            self.metrics[labels] = val
            done(val)
        } else {
            self.value -= amount
            done(self.value)
        }
        }
    }
    
    /// Decrements the Gauge
    ///
    /// - Parameters:
    ///     - labels: Labels to attach to the value
    ///
    public func dec(_ labels: Labels? = nil, _ done: @escaping (NumType) -> Void = { _ in }) {
        self.dec(1, labels) {
            done($0)
        }
    }
    
    /// Gets the value of the Gauge
    ///
    /// - Parameters:
    ///     - labels: Labels to get the value for
    ///
    /// - Returns: The value of the Gauge attached to the provided labels
    public func get(_ labels: Labels? = nil) -> NumType {
        if let labels = labels {
            return self.metrics[labels] ?? initialValue
        } else {
            return self.value
        }
    }
}
