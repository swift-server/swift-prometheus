/// Info metric
///
/// Info tracks key-value information, usually about a whole target
public class Info<Labels: MetricLabels>: Metric, PrometheusHandled {
    /// Prometheus instance that created this Info
    internal let prometheus: Prometheus
    
    /// Name of the Info, required
    public let name: String
    /// Help text of the Info, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: MetricType = .info
    
    /// Labels of the info
    /// For Info metrics, these are the actual values the metric is exposing
    internal var labels = Labels()
    
    /// Creates a new Info
    ///
    /// - Parameters:
    ///     - name: Name of the Info
    ///     - help: Help text of the Info
    ///     - p: Prometheus instance handling this Info
    internal init(_ name: String, _ help: String? = nil, _ p: Prometheus) {
        self.name = name
        self.help = help
        self.prometheus = p
    }
    
    /// Set the info
    ///
    /// - Parameters:
    ///     - labels: Labels to set the Info to
    public func info(_ labels: Labels) {
        self.labels = labels
    }
    
    /// Gets the metric string for this Info
    ///
    /// - Returns:
    ///     Newline seperated Prometheus formatted metric string
    public func getMetric() -> String {
        var output = [String]()
        
        output.append(headers)
        
        let labelsString = encodeLabels(labels)
        output.append("\(name)\(labelsString) 1.0")
        
        return output.joined(separator: "\n")
    }
}
