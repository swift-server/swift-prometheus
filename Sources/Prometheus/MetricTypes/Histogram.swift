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

public class Histogram<NumType: DoubleRepresentable, Labels: HistogramLabels>: Metric {
    public let name: String
    
    public let help: String?
    
    private var buckets: [Counter<NumType, EmptyCodable>] = []
    
    private var upperBounds: [Double]
    
    private var labels: Labels
    
    private let total: Counter<NumType, EmptyCodable>
    
    internal init(_ name: String, _ help: String? = nil, _ labels: Labels = Labels(), _ buckets: [Double] = defaultBuckets) {
        self.name = name
        self.help = help
        
        self.total = .init("\(self.name)_sum")
        
        self.labels = labels
        
        self.upperBounds = buckets
        
        buckets.forEach { _ in
            self.buckets.append(.init("\(name)_bucket", nil, 0))
        }
    }
    
    public func getMetric() -> String {
        var output = [String]()
        
        if let help = help {
            output.append("# HELP \(name) \(help)")
        }
        output.append("# TYPE \(name) histogram")

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
        
        return output.joined(separator: "\n")
    }
    
    public func observe(_ value: NumType) {
        self.total.inc(value)
        
        for (i, bound) in self.upperBounds.enumerated() {
            if bound >= value.doubleValue {
                buckets[i].inc()
                return
            }
        }
    }
}
