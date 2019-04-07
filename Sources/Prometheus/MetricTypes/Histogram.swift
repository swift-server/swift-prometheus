/// Default buckets used by Histograms
public var defaultBuckets = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0, Double.greatestFiniteMagnitude]

/// Label type Histograms can use
public protocol HistogramLabels: MetricLabels {
    var le: String { get set }
}

extension HistogramLabels {
    /// Creates empty HistogramLabels
    init() {
        self.init()
        self.le = ""
    }
}

/// Prometheus Counter metric
///
/// See https://prometheus.io/docs/concepts/metric_types/#Histogram
public class Histogram<NumType: DoubleRepresentable, Labels: HistogramLabels>: Metric, PrometheusHandled {
    /// Prometheus instance that created this Histogram
    internal let prometheus: PrometheusClient
    
    /// Name of this Histogram, required
    public let name: String
    /// Help text of this Histogram, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: MetricType = .histogram
    
    /// Bucketed values for this Histogram
    private var buckets: [Counter<NumType, EmptyLabels>] = []
    
    /// Buckets used by this Histogram
    internal let upperBounds: [Double]
    
    /// Labels for this Histogram
    internal private(set) var labels: Labels
    
    /// Sub Histograms for this Histogram
    fileprivate var subHistograms: [Histogram<NumType, Labels>] = []
    
    /// Total value of the Histogram
    private let total: Counter<NumType, EmptyLabels>
    
    /// Creates a new Histogram
    ///
    /// - Parameters:
    ///     - name: Name of the Histogram
    ///     - help: Help text of the Histogram
    ///     - labels: Labels for the Histogram
    ///     - buckets: Buckets to use for the Histogram
    ///     - p: Prometheus instance creating this Histogram
    internal init(_ name: String, _ help: String? = nil, _ labels: Labels = Labels(), _ buckets: [Double] = defaultBuckets, _ p: PrometheusClient) {
        self.name = name
        self.help = help
        
        self.prometheus = p
        
        self.total = .init("\(self.name)_sum", nil, 0, p)
        
        self.labels = labels
        
        self.upperBounds = buckets
        
        buckets.forEach { _ in
            self.buckets.append(.init("\(name)_bucket", nil, 0, p))
        }
    }
    
    /// Gets the metric string for this Histogram
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

            var acc: NumType = 0
            for (i, bound) in self.upperBounds.enumerated() {
                acc += self.buckets[i].get()
                self.labels.le = bound.description
                let labelsString = encodeLabels(self.labels)
                output.append("\(self.name)_bucket\(labelsString) \(acc)")
            }
            
            let labelsString = encodeLabels(self.labels, ["le"])
            output.append("\(self.name)_count\(labelsString) \(acc)")
            
            output.append("\(self.name)_sum\(labelsString) \(self.total.get())")
            
            self.subHistograms.forEach { subHistogram in
                var acc: NumType = 0
                for (i, bound) in subHistogram.upperBounds.enumerated() {
                    acc += subHistogram.buckets[i].get()
                    subHistogram.labels.le = bound.description
                    let labelsString = encodeLabels(subHistogram.labels)
                    output.append("\(subHistogram.name)_bucket\(labelsString) \(acc)")
                }
                
                let labelsString = encodeLabels(subHistogram.labels, ["le"])
                output.append("\(subHistogram.name)_count\(labelsString) \(acc)")
                
                output.append("\(subHistogram.name)_sum\(labelsString) \(subHistogram.total.get())")
                
                subHistogram.labels.le = ""
            }
            
            self.labels.le = ""
            
            done(output.joined(separator: "\n"))
        }
    }
    
    /// Observe a value
    ///
    /// - Parameters:
    ///     - value: Value to observe
    ///     - labels: Labels to attach to the observed value
    ///     - done: Completion handler
    ///     - observedValue: Value written to the histogram
    public func observe(_ value: NumType, _ labels: Labels? = nil, _ done: @escaping () -> Void = { }) {
        prometheusQueue.async(flags: .barrier) {
            if let labels = labels, type(of: labels) != type(of: EmptySummaryLabels()) {
                let his = self.prometheus.getOrCreateHistogram(with: labels, for: self)
                his.observe(value, nil, done)
            }
            self.total.inc(value)
            
            for (i, bound) in self.upperBounds.enumerated() {
                if bound >= value.doubleValue {
                    self.buckets[i].inc()
                    break
                }
            }
            
            // Only run the callback once; not on both the label and without labels
            if labels == nil {
                done(value)
            }
        }
    }
}

extension PrometheusClient {
    fileprivate func getOrCreateHistogram<T: Numeric, U: HistogramLabels>(with labels: U, for his: Histogram<T, U>) -> Histogram<T, U> {
        let histograms = his.subHistograms.filter { (metric) -> Bool in
            guard metric.name == his.name, metric.help == his.help, metric.labels == labels else { return false }
            return true
        }
        if histograms.count > 2 { fatalError("Somehow got 2 histograms with the same data type") }
        if let histogram = histograms.first {
            return histogram
        } else {
            let histogram = Histogram<T, U>(his.name, his.help, labels, his.upperBounds, self)
            his.subHistograms.append(histogram)
            return histogram
        }
    }
}
