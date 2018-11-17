public protocol SummaryLabels: MetricLabels {
    var quantile: String { get set }
}

extension SummaryLabels {
    init() {
        self.init()
        self.quantile = ""
    }
}

public class Summary<NumType: DoubleRepresentable, Labels: SummaryLabels>: Metric {
    public var name: String
    
    public var help: String?
    
    public var labels: Labels
    
    private var sum: Counter<NumType, EmptyCodable>
    
    private var count: Counter<NumType, EmptyCodable>
    
    private var values: [NumType] = []
    
    public init(_ name: String, _ help: String? = nil, _ labels: Labels = Labels()) {
        self.name = name
        self.help = help
        
        self.sum = .init("\(self.name)_sum")
        
        self.count = .init("\(self.name)_count")
        
        self.labels = labels
    }
    
    public func getMetric() -> String {
        var output = [String]()
        
        if let help = help {
            output.append("# HELP \(name) \(help)")
        }
        output.append("# TYPE \(name) summary")
        
        let quantiles = [0.5, 0.9, 0.99]
        
        calculateQuantiles(quantiles: quantiles, values: values.map { $0.doubleValue }).forEach { (arg) in
            let (q, v) = arg
            self.labels.quantile = "\(q)"
            let labelsString = encodeLabels(self.labels)
            output.append("\(name)\(labelsString) \(v)")
        }
        
        let labelsString = encodeLabels(self.labels, ["quantile"])
        output.append("\(name)_count\(labelsString) \(count.get())")
        output.append("\(name)_sum\(labelsString) \(sum.get())")

        return output.joined(separator: "\n")
    }
    
    public func observe(_ value: NumType) {
        self.count.inc(1)
        self.sum.inc(value)
        self.values.append(value)
    }
}
