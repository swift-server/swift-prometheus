import NIOConcurrencyHelpers

enum Bucket {
    /// Default buckets used by Histograms
    public static let defaultBuckets = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0, Double.greatestFiniteMagnitude]

    public static func linear(start: Double, width: Double, count: Int) -> [Double] {
        assert(count > 1, "Bucket.linear needs a count larger than 1")
        var arr = [Double]()
        var s = start
        for x in 0..<count {
            arr[x] = s
            s += width
        }
        return arr
    }
    
    public static func exponential(start: Double, factor: Double, count: Int) -> [Double] {
        assert(count > 1, "Bucket.exponential needs a count larger than 1")
        assert(start > 0, "Bucket.exponential needs a start larger than 0")
        assert(factor > 1, "Bucket.exponential needs a factor larger than 1")
        var arr = [Double]()
        var s = start
        for x in 0..<count {
            arr[x] = s
            s *= factor
        }
        return arr
    }
}

/// Label type Histograms can use
public protocol HistogramLabels: MetricLabels {
    /// Bucket
    var le: String { get set }
}

extension HistogramLabels {
    /// Creates empty HistogramLabels
    init() {
        self.init()
        self.le = ""
    }
}

/// Prometheus Histogram metric
///
/// See https://prometheus.io/docs/concepts/metric_types/#Histogram
public class PromHistogram<NumType: DoubleRepresentable, Labels: HistogramLabels>: PromMetric, PrometheusHandled {
    /// Prometheus instance that created this Histogram
    internal weak var prometheus: PrometheusClient?
    
    /// Name of this Histogram, required
    public let name: String
    /// Help text of this Histogram, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: PromMetricType = .histogram
    
    /// Bucketed values for this Histogram
    private var buckets: [PromCounter<NumType, EmptyLabels>] = []
    
    /// Buckets used by this Histogram
    internal let upperBounds: [Double]
    
    /// Labels for this Histogram
    internal private(set) var labels: Labels
    
    /// Sub Histograms for this Histogram
    fileprivate var subHistograms: [PromHistogram<NumType, Labels>] = []
    
    /// Total value of the Histogram
    private let sum: PromCounter<NumType, EmptyLabels>
    
    /// Lock used for thread safety
    private let lock: Lock
    
    /// Creates a new Histogram
    ///
    /// - Parameters:
    ///     - name: Name of the Histogram
    ///     - help: Help text of the Histogram
    ///     - labels: Labels for the Histogram
    ///     - buckets: Buckets to use for the Histogram
    ///     - p: Prometheus instance creating this Histogram
    internal init(_ name: String, _ help: String? = nil, _ labels: Labels = Labels(), _ buckets: [Double] = Bucket.defaultBuckets, _ p: PrometheusClient) {
        self.name = name
        self.help = help
        
        self.prometheus = p
        
        self.sum = .init("\(self.name)_sum", nil, 0, p)
        
        self.labels = labels
        
        self.upperBounds = buckets
        
        self.lock = Lock()
        
        buckets.forEach { _ in
            self.buckets.append(.init("\(name)_bucket", nil, 0, p))
        }
    }
    
    /// Gets the metric string for this Histogram
    ///
    /// - Returns:
    ///     Newline separated Prometheus formatted metric string
    public func collect() -> String {
        return self.lock.withLock {
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
            
            output.append("\(self.name)_sum\(labelsString) \(self.sum.get())")
            
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
                
                output.append("\(subHistogram.name)_sum\(labelsString) \(subHistogram.sum.get())")
                
                subHistogram.labels.le = ""
            }
            
            self.labels.le = ""
            
            return output.joined(separator: "\n")
        }
    }
    
    /// Observe a value
    ///
    /// - Parameters:
    ///     - value: Value to observe
    ///     - labels: Labels to attach to the observed value
    public func observe(_ value: NumType, _ labels: Labels? = nil) {
        self.lock.withLock {
            if let labels = labels, type(of: labels) != type(of: EmptySummaryLabels()) {
                guard let his = self.prometheus?.getOrCreateHistogram(with: labels, for: self) else { fatalError("Lingering Histogram") }
                his.observe(value)
            }
            self.sum.inc(value)
            
            for (i, bound) in self.upperBounds.enumerated() {
                if bound >= value.doubleValue {
                    self.buckets[i].inc()
                    return
                }
            }
        }
    }

}

extension PrometheusClient {
    /// Helper for histograms & labels
    fileprivate func getOrCreateHistogram<T: Numeric, U: HistogramLabels>(with labels: U, for histogram: PromHistogram<T, U>) -> PromHistogram<T, U> {
        let histograms = histogram.subHistograms.filter { (metric) -> Bool in
            guard metric.name == histogram.name, metric.help == histogram.help, metric.labels == labels else { return false }
            return true
        }
        if histograms.count > 2 { fatalError("Somehow got 2 histograms with the same data type") }
        if let histogram = histograms.first {
            return histogram
        } else {
            let newHistogram = PromHistogram<T, U>(histogram.name, histogram.help, labels, histogram.upperBounds, self)
            histogram.subHistograms.append(newHistogram)
            return newHistogram
        }
    }
}
