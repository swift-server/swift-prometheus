public var defaultBuckets = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0, Double.greatestFiniteMagnitude]

public protocol HistogramLabels: MetricLabels {
    var le: String { get set }
}

extension HistogramLabels {
    init() {
        self.init()
        self.le = ""
    }
}

public class Histogram<NumType: DoubleRepresentable, Labels: HistogramLabels>: Metric, PrometheusHandled {
    internal let prometheus: Prometheus
    
    public let name: String
    public let help: String?
    
    public var _type: MetricType = .histogram
    
    private var buckets: [Counter<NumType, EmptyCodable>] = []
    
    internal let upperBounds: [Double]
    
    internal private(set) var labels: Labels
    
    fileprivate var subHistograms: [Histogram<NumType, Labels>] = []
    
    private let total: Counter<NumType, EmptyCodable>
    
    internal init(_ name: String, _ help: String? = nil, _ labels: Labels = Labels(), _ buckets: [Double] = defaultBuckets, _ p: Prometheus) {
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
    
    public func getMetric() -> String {
        var output = [String]()
        
        
        output.append(headers)

        var acc: NumType = 0
        for (i, bound) in self.upperBounds.enumerated() {
            acc += buckets[i].get()
            labels.le = bound.description
            let labelsString = encodeLabels(labels)
            output.append("\(name)_bucket\(labelsString) \(acc)")
        }
        
        let labelsString = encodeLabels(labels, ["le"])
        output.append("\(name)_count\(labelsString) \(acc)")
        
        output.append("\(name)_sum\(labelsString) \(total.get())")
        
        subHistograms.forEach { subHistogram in
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
        }
        
        return output.joined(separator: "\n")
    }
    
    public func observe(_ value: NumType, _ labels: Labels? = nil) {
        if let labels = labels, type(of: labels) != type(of: EmptySummaryCodable()) {
            let his = prometheus.getOrCreateHistogram(with: labels, for: self)
            his.observe(value)
            return
        }
        self.total.inc(value)
        
        for (i, bound) in self.upperBounds.enumerated() {
            if bound >= value.doubleValue {
                buckets[i].inc()
                return
            }
        }
    }
}

extension Prometheus {
    fileprivate func getOrCreateHistogram<T: Numeric, U: HistogramLabels>(with labels: U, for his: Histogram<T, U>) -> Histogram<T, U> {
        let histograms = his.subHistograms.filter { (metric) -> Bool in
            guard metric.name == his.name, metric.help == his.help, metric.labels == labels else { return false }
            return true
            }
        if histograms.count > 2 { fatalError("Somehow got 2 summaries with the same data type") }
        if let histogram = histograms.first {
            return histogram
        } else {
            let histogram = Histogram<T, U>(his.name, his.help, labels, his.upperBounds, self)
            his.subHistograms.append(histogram)
            return histogram
        }
    }
}
