import NIOConcurrencyHelpers
import struct CoreMetrics.TimeUnit
import Dispatch

/// Label type Summaries can use
public protocol SummaryLabels: MetricLabels {
    /// Quantile used to label the summary.
    var quantile: String { get set }
}

extension SummaryLabels {
    /// Creates empty SummaryLabels
    init() {
        self.init()
        self.quantile = ""
    }
}

/// Prometheus Summary metric
///
/// See https://prometheus.io/docs/concepts/metric_types/#summary
public class PromSummary<NumType: DoubleRepresentable, Labels: SummaryLabels>: PromMetric, PrometheusHandled {
    /// Prometheus instance that created this Summary
    internal weak var prometheus: PrometheusClient?
    
    /// Name of this Summary, required
    public let name: String
    /// Help text of this Summary, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: PromMetricType = .summary
    
    private var displayUnit: TimeUnit?
    
    /// Labels for this Summary
    internal private(set) var labels: Labels
    
    /// Sum of the values in this Summary
    private let sum: PromCounter<NumType, EmptyLabels>
    
    /// Amount of values in this Summary
    private let count: PromCounter<NumType, EmptyLabels>
    
    /// Values in this Summary
    private var values: [NumType] = []

    /// Number of last values used to calculate quantiles
    internal let capacity: Int

    /// Quantiles used by this Summary
    internal let quantiles: [Double]
    
    /// Sub Summaries for this Summary
    fileprivate var subSummaries: [PromSummary<NumType, Labels>] = []
    
    /// Lock used for thread safety
    private let lock: Lock
    
    /// Creates a new Summary
    ///
    /// - Parameters:
    ///     - name: Name of the Summary
    ///     - help: Help text of the Summary
    ///     - labels: Labels for the Summary
    ///     - capacity: Number of last values used to calculate quantiles
    ///     - quantiles: Quantiles to use for the Summary
    ///     - p: Prometheus instance creating this Summary
    internal init(_ name: String, _ help: String? = nil, _ labels: Labels = Labels(), _ capacity: Int = Prometheus.defaultSummaryCapacity, _ quantiles: [Double] = Prometheus.defaultQuantiles, _ p: PrometheusClient) {
        self.name = name
        self.help = help
        
        self.prometheus = p
        
        self.displayUnit = nil
        
        self.sum = .init("\(self.name)_sum", nil, 0, p)
        
        self.count = .init("\(self.name)_count", nil, 0, p)
        
        self.capacity = capacity

        self.quantiles = quantiles
        
        self.labels = labels
        
        self.lock = Lock()
    }
    
    /// Gets the metric string for this Summary
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

            calculateQuantiles(quantiles: self.quantiles, values: self.values.map { $0.doubleValue }).sorted { $0.key < $1.key }.forEach { (arg) in
                let (q, v) = arg
                self.labels.quantile = "\(q)"
                let labelsString = encodeLabels(self.labels)
                output.append("\(self.name)\(labelsString) \(format(v))")
            }
            
            let labelsString = encodeLabels(self.labels, ["quantile"])
            output.append("\(self.name)_count\(labelsString) \(self.count.get())")
            output.append("\(self.name)_sum\(labelsString) \(format(self.sum.get().doubleValue))")
            
            self.subSummaries.forEach { subSum in
                calculateQuantiles(quantiles: self.quantiles, values: subSum.values.map { $0.doubleValue }).sorted { $0.key < $1.key }.forEach { (arg) in
                    let (q, v) = arg
                    subSum.labels.quantile = "\(q)"
                    let labelsString = encodeLabels(subSum.labels)
                    output.append("\(subSum.name)\(labelsString) \(format(v))")
                }
                
                let labelsString = encodeLabels(subSum.labels, ["quantile"])
                output.append("\(subSum.name)_count\(labelsString) \(subSum.count.get())")
                output.append("\(subSum.name)_sum\(labelsString) \(format(subSum.sum.get().doubleValue))")
                subSum.labels.quantile = ""
            }
            
            self.labels.quantile = ""
            
            return output.joined(separator: "\n")
        }
    }
    
    // Updated for SwiftMetrics 2.0 to be unit agnostic if displayUnit is set or default to nanoseconds.
    private func format(_ v: Double) -> Double {
        let displayUnitScale = self.displayUnit?.scaleFromNanoseconds ?? 1
        return v / Double(displayUnitScale)
    }
    
    internal func preferDisplayUnit(_ unit: TimeUnit) {
        self.lock.withLock {
            self.displayUnit = unit
        }
    }
    
    /// Record a value
    ///
    /// - Parameters:
    ///     - duration: Duration to record
    public func recordNanoseconds(_ duration: Int64) {
        guard let v = NumType.init(exactly: duration) else { return }
        self.observe(v)
    }
    
    /// Observe a value
    ///
    /// - Parameters:
    ///     - value: Value to observe
    ///     - labels: Labels to attach to the observed value
    public func observe(_ value: NumType, _ labels: Labels? = nil) {
        self.lock.withLock {
            if let labels = labels, type(of: labels) != type(of: EmptySummaryLabels()) {
                guard let sum = self.prometheus?.getOrCreateSummary(withLabels: labels, forSummary: self) else { fatalError("Lingering Summary") }
                sum.observe(value)
            }
            self.count.inc(1)
            self.sum.inc(value)
            self.values.append(value)
            if self.values.count > self.capacity {
                self.values.remove(at: 0)
            }
        }
    }
    
    /// Time the duration of a closure and observe the resulting time in seconds.
    ///
    /// - parameters:
    ///     - labels: Labels to attach to the resulting value.
    ///     - body: Closure to run & record.
    @inlinable
    public func time<T>(_ labels: Labels? = nil, _ body: @escaping () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let delta = Double(DispatchTime.now().uptimeNanoseconds - start)
            self.observe(.init(delta / 1_000_000_000), labels)
        }
        return try body()
    }
}

extension PrometheusClient {
    /// Helper for summaries & labels
    fileprivate func getOrCreateSummary<T: Numeric, U: SummaryLabels>(withLabels labels: U, forSummary summary: PromSummary<T, U>) -> PromSummary<T, U> {
        let summaries = summary.subSummaries.filter { (metric) -> Bool in
            guard metric.name == summary.name, metric.help == summary.help, metric.labels == labels else { return false }
            return true
        }
        if summaries.count > 2 { fatalError("Somehow got 2 summaries with the same data type") }
        if let summary = summaries.first {
            return summary
        } else {
            let newSummary = PromSummary<T, U>(summary.name, summary.help, labels, summary.capacity, summary.quantiles, self)
            summary.subSummaries.append(newSummary)
            return newSummary
        }
    }
}

/// Calculates values per quantile
///
/// - Parameters:
///     - quantiles: Quantiles to divide values over
///     - values: Values to divide over quantiles
///
/// - Returns: Dictionary of type [Quantile: Value]
func calculateQuantiles(quantiles: [Double], values: [Double]) -> [Double: Double] {
    let values = values.sorted()
    var quantilesMap: [Double: Double] = [:]
    quantiles.forEach { (q) in
        quantilesMap[q] = quantile(q, values)
    }
    return quantilesMap
}

/// Calculates value for quantile
///
/// - Parameters:
///     - q: Quantile to calculate value for
///     - values: Values to calculate quantile from
///
/// - Returns: Calculated quantile
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
