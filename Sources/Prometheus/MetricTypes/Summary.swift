public var defaultQuantiles = [0.01, 0.05, 0.5, 0.9, 0.95, 0.99, 0.999]

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
    public let name: String
    
    public let help: String?
    
    private var labels: Labels
    
    private let sum: Counter<NumType, EmptyCodable>
    
    private let count: Counter<NumType, EmptyCodable>
    
    private var values: [NumType] = []
    
    private var quantiles: [Double]
    
    internal init(_ name: String, _ help: String? = nil, _ quantiles: [Double] = defaultQuantiles, _ labels: Labels = Labels()) {
        self.name = name
        self.help = help
        
        self.sum = .init("\(self.name)_sum")
        
        self.count = .init("\(self.name)_count")
        
        self.quantiles = quantiles
        
        self.labels = labels
    }
    
    public func getMetric() -> String {
        var output = [String]()
        
        if let help = help {
            output.append("# HELP \(name) \(help)")
        }
        output.append("# TYPE \(name) summary")
        
        calculateQuantiles(quantiles: quantiles, values: values.map { $0.doubleValue }).sorted { $0.key < $1.key }.forEach { (arg) in
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
