import NIOConcurrencyHelpers
import NIO
import struct CoreMetrics.TimeUnit
import Dispatch

/// Prometheus Summary metric
///
/// See https://prometheus.io/docs/concepts/metric_types/#summary
public class PromSummary<NumType: DoubleRepresentable>: PromMetric, PrometheusHandled {
    /// Prometheus instance that created this Summary
    internal weak var prometheus: PrometheusClient?
    
    /// Name of this Summary, required
    public let name: String
    /// Help text of this Summary, optional
    public let help: String?
    
    /// Type of the metric, used for formatting
    public let _type: PromMetricType = .summary
    
    private var displayUnit: TimeUnit?
    
    /// Sum of the values in this Summary
    private let sum: PromCounter<NumType>
    
    /// Amount of values in this Summary
    private let count: PromCounter<NumType>
    
    /// Values in this Summary
    private var values: CircularBuffer<NumType>

    /// Number of values to keep for calculating quantiles
    internal let capacity: Int

    /// Quantiles used by this Summary
    internal let quantiles: [Double]
    
    /// Sub Summaries for this Summary
    fileprivate var subSummaries: [DimensionLabels: PromSummary<NumType>] = [:]
    
    /// Lock used for thread safety
    private let lock: Lock
    
    /// Creates a new Summary
    ///
    /// - Parameters:
    ///     - name: Name of the Summary
    ///     - help: Help text of the Summary
    ///     - labels: Labels for the Summary
    ///     - capacity: Number of values to keep for calculating quantiles
    ///     - quantiles: Quantiles to use for the Summary
    ///     - p: Prometheus instance creating this Summary
    internal init(_ name: String, _ help: String? = nil, _ capacity: Int = Prometheus.defaultSummaryCapacity, _ quantiles: [Double] = Prometheus.defaultQuantiles, _ p: PrometheusClient) {
        self.name = name
        self.help = help
        
        self.prometheus = p
        
        self.displayUnit = nil
        
        self.sum = .init("\(self.name)_sum", nil, 0, p)
        
        self.count = .init("\(self.name)_count", nil, 0, p)
        
        self.values = CircularBuffer(initialCapacity: capacity)

        self.capacity = capacity

        self.quantiles = quantiles

        self.lock = Lock()
    }
    
    /// Gets the metric string for this Summary
    ///
    /// - Returns:
    ///     Newline separated Prometheus formatted metric string
    public func collect() -> String {
        let (subSummaries, values) = lock.withLock {
            (self.subSummaries, self.values)
        }

        var output = [String]()
        // HELP/TYPE + (summary + subSummaries) * (quantiles + sum + count)
        output.reserveCapacity(2 + (subSummaries.count + 1) * (quantiles.count + 2))

        if let help = self.help {
            output.append("# HELP \(self.name) \(help)")
        }
        output.append("# TYPE \(self.name) \(self._type)")
        calculateQuantiles(quantiles: self.quantiles, values: values.map { $0.doubleValue }).sorted { $0.key < $1.key }.forEach { (arg) in
            let (q, v) = arg
            let labelsString = encodeLabels(EncodableSummaryLabels(labels: nil, quantile: "\(q)"))
            output.append("\(self.name)\(labelsString) \(format(v))")
        }

//        let labelsString = encodeLabels(labels, ["quantile"])
        output.append("\(self.name)_count \(self.count.get())")
        output.append("\(self.name)_sum \(format(self.sum.get().doubleValue))")

        subSummaries.forEach { labels, subSum in
            let subSumValues = lock.withLock { subSum.values }
            calculateQuantiles(quantiles: self.quantiles, values: subSumValues.map { $0.doubleValue }).sorted { $0.key < $1.key }.forEach { (arg) in
                let (q, v) = arg
                let labelsString = encodeLabels(EncodableSummaryLabels(labels: labels, quantile: "\(q)"))
                output.append("\(subSum.name)\(labelsString) \(format(v))")
            }

            let labelsString = encodeLabels(EncodableSummaryLabels(labels: labels, quantile: nil))
            output.append("\(subSum.name)_count\(labelsString) \(subSum.count.get())")
            output.append("\(subSum.name)_sum\(labelsString) \(format(subSum.sum.get().doubleValue))")
        }

        return output.joined(separator: "\n")
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
    public func observe(_ value: NumType, _ labels: DimensionLabels? = nil) {
        if let labels = labels {
            let sum = self.getOrCreateSummary(withLabels: labels)
            sum.observe(value)
        }
        self.count.inc(1)
        self.sum.inc(value)
        self.lock.withLock {
            if self.values.count == self.capacity {
                _ = self.values.popFirst()
            }
            self.values.append(value)
        }
    }
    
    /// Time the duration of a closure and observe the resulting time in seconds.
    ///
    /// - parameters:
    ///     - labels: Labels to attach to the resulting value.
    ///     - body: Closure to run & record.
    @inlinable
    public func time<T>(_ labels: DimensionLabels? = nil, _ body: @escaping () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let delta = Double(DispatchTime.now().uptimeNanoseconds - start)
            self.observe(.init(delta / 1_000_000_000), labels)
        }
        return try body()
    }
    fileprivate func getOrCreateSummary(withLabels labels: DimensionLabels) -> PromSummary<NumType> {
        let subSummaries = self.lock.withLock { self.subSummaries }
        if let summary = subSummaries[labels] {
            precondition(summary.name == self.name,
                         """
                         Somehow got 2 subSummaries with the same data type  / labels 
                         but different names: expected \(self.name), got \(summary.name)
                         """)
            precondition(summary.help == self.help,
                         """
                         Somehow got 2 subSummaries with the same data type  / labels 
                         but different help messages: expected \(self.help ?? "nil"), got \(summary.help ?? "nil")
                         """)
            return summary
        } else {
            return lock.withLock {
                if let summary = self.subSummaries[labels] {
                    precondition(summary.name == self.name,
                                 """
                                 Somehow got 2 subSummaries with the same data type  / labels 
                                 but different names: expected \(self.name), got \(summary.name)
                                 """)
                    precondition(summary.help == self.help,
                                 """
                                 Somehow got 2 subSummaries with the same data type  / labels 
                                 but different help messages: expected \(self.help ?? "nil"), got \(summary.help ?? "nil")
                                 """)
                    return summary
                }
                guard let prometheus = prometheus else {
                    fatalError("Lingering Summary")
                }
                let newSummary = PromSummary(self.name, self.help, self.capacity, self.quantiles, prometheus)
                self.subSummaries[labels] = newSummary
                return newSummary
            }
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
