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

public class Summary<NumType: DoubleRepresentable, Labels: SummaryLabels>: Metric, PrometheusHandled {
    internal let prometheus: Prometheus
    
    public let name: String
    public let help: String?
    
    internal private(set) var labels: Labels
    
    private let sum: Counter<NumType, EmptyCodable>
    
    private let count: Counter<NumType, EmptyCodable>
    
    private var values: [NumType] = []
    
    internal let quantiles: [Double]
    
    internal init(_ name: String, _ help: String? = nil, _ quantiles: [Double] = defaultQuantiles, _ labels: Labels = Labels(), _ p: Prometheus) {
        self.name = name
        self.help = help
        
        self.prometheus = p
        
        self.sum = .init("\(self.name)_sum", nil, 0, p)
        
        self.count = .init("\(self.name)_count", nil, 0, p)
        
        self.quantiles = quantiles
        
        self.labels = labels
    }
    
    public func getMetric() -> String {
        var output = [String]()
        
        if self.labels == Labels() {
            if let help = help {
                output.append("# HELP \(name) \(help)")
            }
            output.append("# TYPE \(name) summary")
        }
        
        calculateQuantiles(quantiles: quantiles, values: values.map { $0.doubleValue }).sorted { $0.key < $1.key }.forEach { (arg) in
            let (q, v) = arg
            self.labels.quantile = "\(q)"
            let labelsString = encodeLabels(self.labels)
            output.append("\(name)\(labelsString) \(v)")
        }
        
        let labelsString = encodeLabels(self.labels, ["quantile"])
        output.append("\(name)_count\(labelsString) \(count.get())")
        output.append("\(name)_sum\(labelsString) \(sum.get())")
        
        self.labels.quantile = ""
        
        return output.joined(separator: "\n")
    }
    
    public func observe(_ value: NumType, _ labels: Labels? = nil) {
        if let labels = labels, type(of: labels) != type(of: EmptySummaryCodable()) {
            let sum = self.prometheus.getOrCreateSummary(withLabels: labels, forSummary: self)
            sum.observe(value)
            return
        }
        self.count.inc(1)
        self.sum.inc(value)
        self.values.append(value)
    }
}

extension Prometheus {
    fileprivate func getOrCreateSummary<T: Numeric, U: SummaryLabels>(withLabels labels: U, forSummary sum: Summary<T, U>) -> Summary<T, U> {
        let summary = metrics.filter { (metric) -> Bool in
            guard let metric = metric as? Summary<T, U> else { return false }
            guard metric.name == sum.name, metric.help == sum.help, metric.labels == labels else { return false }
            return true
        } as? [Summary<T, U>] ?? []
        if summary.count > 2 { fatalError("Somehow got 2 summaries with the same data type") }
        if let summary = summary.first {
            return summary
        } else {
            return createSummary(forType: T.self, named: sum.name, helpText: sum.help, quantiles: sum.quantiles, labels: labels)
        }
    }
}

func calculateQuantiles(quantiles: [Double], values: [Double]) -> [Double: Double] {
    let values = values.sorted()
    var quantilesMap: [Double: Double] = [:]
    quantiles.forEach { (q) in
        quantilesMap[q] = quantile(q, values)
    }
    return quantilesMap
}

func quantile(_ q: Double, _ values: [Double]) -> Double {
    if values.count == 0 {
        return 0
    }
    if values.count == 1 {
        return values[0]
    }
    
    let n = Double(values.count)
    if let pos = Int(exactly: n*q) {
        if pos < 2 {
            return values[0]
        } else if pos == values.count {
            return values[pos - 1]
        }
        return (values[pos - 1] + values[pos]) / 2.0
    } else {
        let pos = Int((n*q).rounded(.up))
        return values[pos - 1]
    }
}
