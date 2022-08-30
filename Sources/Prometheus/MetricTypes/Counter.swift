import NIOConcurrencyHelpers

/// Prometheus Counter metric
///
/// See: https://prometheus.io/docs/concepts/metric_types/#counter
public class PromCounter<NumType: Numeric>: PromMetric {
    /// Name of the Counter, required
    public let name: String
    /// Help text of the Counter, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: PromMetricType = .counter
    
    /// Current value of the counter
    internal var value: NumType
    
    /// Initial value of the counter
    private let initialValue: NumType
    
    /// Storage of values that have labels attached
    internal var metrics: [DimensionLabels: NumType] = [:]
    
    /// Lock used for thread safety
    internal let lock: Lock
    
    /// Creates a new instance of a Counter
    ///
    /// - Parameters:
    ///     - name: Name of the Counter
    ///     - help: Help text of the Counter
    ///     - initialValue: Initial value to set the counter to
    ///     - p: Prometheus instance that created this counter
    internal init(_ name: String, _ help: String? = nil, _ initialValue: NumType = 0) {
        self.name = name
        self.help = help
        self.initialValue = initialValue
        self.value = initialValue
        self.lock = Lock()
    }
    
    /// Gets the metric string for this counter
    ///
    /// - Returns:
    ///     Newline separated Prometheus formatted metric string
    public func collect() -> String {
        let (value, metrics) = self.lock.withLock {
            (self.value, self.metrics)
        }
        var output = [String]()

        if let help = self.help {
            output.append("# HELP \(self.name) \(help)")
        }
        output.append("# TYPE \(self.name) \(self._type)")

        output.append("\(self.name) \(value)")

        metrics.forEach { (labels, value) in
            let labelsString = encodeLabels(labels)
            output.append("\(self.name)\(labelsString) \(value)")
        }

        return output.joined(separator: "\n")
    }
    
    /// Increments the Counter
    ///
    /// - Parameters:
    ///     - amount: Amount to increment the counter with
    ///     - labels: Labels to attach to the value
    ///
    @discardableResult
    public func inc(_ amount: NumType = 1, _ labels: DimensionLabels? = nil) -> NumType {
        return self.lock.withLock {
            if let labels = labels {
                var val = self.metrics[labels] ?? self.initialValue
                val += amount
                self.metrics[labels] = val
                return val
            } else {
                self.value += amount
                return self.value
            }
        }
    }
    
    /// Gets the value of the Counter
    ///
    /// - Parameters:
    ///     - labels: Labels to get the value for
    ///
    /// - Returns: The value of the Counter attached to the provided labels
    public func get(_ labels: DimensionLabels? = nil) -> NumType {
        return self.lock.withLock {
            if let labels = labels {
                return self.metrics[labels] ?? initialValue
            } else {
                return self.value
            }
        }
    }
}
