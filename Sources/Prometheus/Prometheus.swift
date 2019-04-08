/// Prometheus class
///
/// See https://prometheus.io/docs/introduction/overview/
public class PrometheusClient: MetricsFactory {
    /// Makes a counter
    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        if let counter = self.metrics.filter({ (m) -> Bool in
            return m._type == .counter && m.name == label
        }).first as? CounterHandler {
            return counter
        }
        return self.createCounter(forType: Int64.self, named: label, withLabelType: DimensionLabels.self)
    }
    
    /// Makes a recorder
    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        if let recorder = self.metrics.filter({ (m) -> Bool in
            return m._type == (aggregate ? .histogram : .gauge) && m.name == label
        }).first as? RecorderHandler {
            return recorder
        }
        if aggregate {
            return self.createHistogram(forType: Double.self, named: label, labels: DimensionHistogramLabels.self)
        } else {
            return self.createGauge(forType: Double.self, named: label, withLabelType: DimensionLabels.self)
        }
    }
    
    /// Makes a timer
    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        if let timer = self.metrics.filter({ (m) -> Bool in
            return m._type == .summary && m.name == label
        }).first as? TimerHandler {
            return timer
        }
        return self.createSummary(forType: Double.self, named: label, labels: DimensionSummaryLabels.self)
    }
    
    /// Metrics tracked by this Prometheus instance
    internal var metrics: [Metric]
    
    /// Lock used for thread safety
    private let lock: NSLock
    
    /// Create a PrometheusClient instance
    public init() {
        self.metrics = []
        self.lock = NSLock()
    }
    
    /// Creates prometheus formatted metrics
    ///
    /// - Returns: Newline seperated string with metrics for all Metric Trackers of this Prometheus instance
    public func getMetrics() -> String {
        return self.lock.withLock {
            return self.metrics.map { $0.getMetric() }.joined(separator: "\n")
        }
    }
    
    // MARK: - Counter
    
    /// Creates a counter with the given values
    ///
    /// - Parameters:
    ///     - type: Type the counter will count
    ///     - name: Name of the counter
    ///     - helpText: Help text for the counter. Usually a short description
    ///     - initialValue: An initial value to set the counter to, defaults to 0
    ///     - labelType: Type of labels this counter can use. Can be left out to default to no labels
    ///
    /// - Returns: Counter instance
    public func createCounter<T: Numeric, U: MetricLabels>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        initialValue: T = 0,
        withLabelType labelType: U.Type) -> PromCounter<T, U>
    {
        return self.lock.withLock {
            let counter = PromCounter<T, U>(name, helpText, initialValue, self)
            self.metrics.append(counter)
            return counter
        }
    }
    
    /// Creates a counter with the given values
    ///
    /// - Parameters:
    ///     - type: Type the counter will count
    ///     - name: Name of the counter
    ///     - helpText: Help text for the counter. Usually a short description
    ///     - initialValue: An initial value to set the counter to, defaults to 0
    ///
    /// - Returns: Counter instance
    public func createCounter<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        initialValue: T = 0) -> PromCounter<T, EmptyLabels>
    {
        return self.createCounter(forType: type, named: name, helpText: helpText, initialValue: initialValue, withLabelType: EmptyLabels.self)
    }
    
    // MARK: - Gauge
    
    /// Creates a gauge with the given values
    ///
    /// - Parameters:
    ///     - type: Type the gauge will hold
    ///     - name: Name of the gauge
    ///     - helpText: Help text for the gauge. Usually a short description
    ///     - initialValue: An initial value to set the gauge to, defaults to 0
    ///     - labelType: Type of labels this gauge can use. Can be left out to default to no labels
    ///
    /// - Returns: Gauge instance
    public func createGauge<T: Numeric, U: MetricLabels>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        initialValue: T = 0,
        withLabelType labelType: U.Type) -> PromGauge<T, U>
    {
        return self.lock.withLock {
            let gauge = PromGauge<T, U>(name, helpText, initialValue, self)
            self.metrics.append(gauge)
            return gauge
        }
    }
    
    /// Creates a gauge with the given values
    ///
    /// - Parameters:
    ///     - type: Type the gauge will count
    ///     - name: Name of the gauge
    ///     - helpText: Help text for the gauge. Usually a short description
    ///     - initialValue: An initial value to set the gauge to, defaults to 0
    ///
    /// - Returns: Gauge instance
    public func createGauge<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        initialValue: T = 0) -> PromGauge<T, EmptyLabels>
    {
        return self.createGauge(forType: type, named: name, helpText: helpText, initialValue: initialValue, withLabelType: EmptyLabels.self)
    }
    
    // MARK: - Histogram
    
    /// Creates a histogram with the given values
    ///
    /// - Parameters:
    ///     - type: The type the histogram will observe
    ///     - name: Name of the histogram
    ///     - helpText: Help text for the histogram. Usually a short description
    ///     - buckets: Buckets to divide values over
    ///     - labels: Labels to give this histogram. Can be left out to default to no labels
    ///
    /// - Returns: Histogram instance
    public func createHistogram<T: Numeric, U: HistogramLabels>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        buckets: [Double] = defaultBuckets,
        labels: U.Type) -> PromHistogram<T, U>
    {
        return self.lock.withLock {
            let histogram = PromHistogram<T, U>(name, helpText, U(), buckets, self)
            self.metrics.append(histogram)
            return histogram
        }
    }
    
    /// Creates a histogram with the given values
    ///
    /// - Parameters:
    ///     - type: The type the histogram will observe
    ///     - name: Name of the histogram
    ///     - helpText: Help text for the histogram. Usually a short description
    ///     - buckets: Buckets to divide values over
    ///
    /// - Returns: Histogram instance
    public func createHistogram<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        buckets: [Double] = defaultBuckets) -> PromHistogram<T, EmptyHistogramLabels>
    {
        return self.createHistogram(forType: type, named: name, helpText: helpText, buckets: buckets, labels: EmptyHistogramLabels.self)
    }
    
    // MARK: - Summary
    
    /// Creates a summary with the given values
    ///
    /// - Parameters:
    ///     - type: The type the summary will observe
    ///     - name: Name of the summary
    ///     - helpText: Help text for the summary. Usually a short description
    ///     - quantiles: Quantiles to caluculate
    ///     - labels: Labels to give this summary. Can be left out to default to no labels
    ///
    /// - Returns: Summary instance
    public func createSummary<T: Numeric, U: SummaryLabels>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        quantiles: [Double] = defaultQuantiles,
        labels: U.Type) -> PromSummary<T, U>
    {
        return self.lock.withLock {
            let summary = PromSummary<T, U>(name, helpText, U(), quantiles, self)
            self.metrics.append(summary)
            return summary
        }
    }
    
    /// Creates a summary with the given values
    ///
    /// - Parameters:
    ///     - type: The type the summary will observe
    ///     - name: Name of the summary
    ///     - helpText: Help text for the summary. Usually a short description
    ///     - quantiles: Quantiles to caluculate
    ///
    /// - Returns: Summary instance
    public func createSummary<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        quantiles: [Double] = defaultQuantiles) -> PromSummary<T, EmptySummaryLabels>
    {
        return self.createSummary(forType: type, named: name, helpText: helpText, quantiles: quantiles, labels: EmptySummaryLabels.self)
    }
    
    // MARK: - Info
    
    /// Creates an Info metric with the given values
    ///
    /// - Parameters:
    ///     - name: Name of the info
    ///     - helpText: Help text for the info. Usually a short description
    ///     - labelType: Type of labels this Info can use
    ///
    /// - Returns Info instance
    public func createInfo<U: MetricLabels>(
        named name: String,
        helpText: String? = nil,
        labelType: U.Type) -> PromInfo<U>
    {
        return self.lock.withLock {
            let info = PromInfo<U>(name, helpText, self)
            self.metrics.append(info)
            return info
        }
    }
}

/// Prometheus specific errors
enum PrometheusError: Error {
    /// Thrown when a user tries to retrive
    /// a `PromtheusClient` from `MetricsSystem`
    /// but there was no `PrometheusClient` bootstrapped
    case PrometheusFactoryNotBootstrapped
}

public extension MetricsSystem {
    /// Get the bootstrapped `MetricsSystem` as `PrometheusClient`
    ///
    /// - Returns: `PrometheusClient` used to bootstrap `MetricsSystem`
    /// - Throws: `PrometheusError.PrometheusFactoryNotBootstrapped`
    ///             if no `PrometheusClient` was used to bootstrap `MetricsSystem`
    static func prometheus() throws -> PrometheusClient {
        guard let prom = self.factory as? PrometheusClient else {
            throw PrometheusError.PrometheusFactoryNotBootstrapped
        }
        return prom
    }
}
