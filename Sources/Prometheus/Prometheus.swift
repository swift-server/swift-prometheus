import NIOConcurrencyHelpers
import NIO

/// Prometheus class
///
/// See https://prometheus.io/docs/introduction/overview/
public class PrometheusClient {

    /// Metrics tracked by this Prometheus instance
    private var metrics: [PromMetric]
    
    /// To keep track of the type of a metric since  it can not change
    /// througout the lifetime of the program
    private var metricTypeMap: [String: PromMetricType]
    
    /// Lock used for thread safety
    private let lock: Lock
    
    /// Sanitizers used to clean up label values provided through
    /// swift-metrics.
    public let sanitizer: LabelSanitizer
    
    /// Create a PrometheusClient instance
    public init(labelSanitizer sanitizer: LabelSanitizer = PrometheusLabelSanitizer()) {
        self.metrics = []
        self.metricTypeMap = [:]
        self.sanitizer = sanitizer
        self.lock = Lock()
    }
    
    // MARK: - Collection
    
    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - succeed: Closure that will be called with a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(_ succeed: (String) -> ()) {
        self.lock.withLock {
            succeed(self.metrics.map { $0.collect() }.joined(separator: "\n"))
        }
    }
    
    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - promise: Promise that will succeed with a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(into promise: EventLoopPromise<String>) {
        collect(promise.succeed)
    }
    
    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - succeed: Closure that will be called with a `ByteBuffer` containing a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(_ succeed: (ByteBuffer) -> ()) {
        self.lock.withLock {
            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            self.metrics.forEach {
                $0.collect(into: &buffer)
                buffer.writeString("\n")
            }
            succeed(buffer)
        }
    }

    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - promise: Promise that will succeed with a `ByteBuffer` containing a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(into promise: EventLoopPromise<ByteBuffer>) {
        collect(promise.succeed)
    }
    
    // MARK: - Metric Access
    
    public func removeMetric(_ metric: PromMetric) {
        // `metricTypeMap` is left untouched as those must be consistent
        // throughout the lifetime of a program.
        return lock.withLock {
            self.metrics.removeAll { $0._type == metric._type && $0.name == metric.name }
        }
    }
    
    public func getMetricInstance<T>(with name: String, andType type: PromMetricType) -> T? where T: PromMetric {
        return lock.withLock {
            self.metrics.compactMap { $0 as? T }.filter { $0.name == name && $0._type == type }.first
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
        if let counter: PromCounter<T, U> = getMetricInstance(with: name, andType: .counter) {
            return counter
        }

        return self.lock.withLock {
            if let type = metricTypeMap[name] {
                precondition(type == .counter, "Label \(name) was associated with \(type) before. Can not be used for a counter now.")
            }
            let counter = PromCounter<T, U>(name, helpText, initialValue, self)
            self.metricTypeMap[name] = .counter
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
        if let gauge: PromGauge<T, U> = getMetricInstance(with: name, andType: .gauge) {
            return gauge
        }

        return self.lock.withLock {
            if let type = metricTypeMap[name] {
                precondition(type == .gauge, "Label \(name) was associated with \(type) before. Can not be used for a gauge now.")
            }
            let gauge = PromGauge<T, U>(name, helpText, initialValue, self)
            self.metricTypeMap[name] = .gauge
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
        buckets: Buckets = .defaultBuckets,
        labels: U.Type) -> PromHistogram<T, U>
    {
        if let histogram: PromHistogram<T, U> = getMetricInstance(with: name, andType: .histogram) {
            return histogram
        }

        return self.lock.withLock {
            if let type = metricTypeMap[name] {
                precondition(type == .histogram, "Label \(name) was associated with \(type) before. Can not be used for a histogram now.")
            }
            let histogram = PromHistogram<T, U>(name, helpText, U(), buckets, self)
            self.metricTypeMap[name] = .histogram
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
        buckets: Buckets = .defaultBuckets) -> PromHistogram<T, EmptyHistogramLabels>
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
        quantiles: [Double] = Prometheus.defaultQuantiles,
        labels: U.Type) -> PromSummary<T, U>
    {
        if let summary: PromSummary<T, U> = getMetricInstance(with: name, andType: .summary) {
            return summary
        }

        return self.lock.withLock {
            if let type = metricTypeMap[name] {
                precondition(type == .summary, "Label \(name) was associated with \(type) before. Can not be used for a summary now.")
            }
            let summary = PromSummary<T, U>(name, helpText, U(), quantiles, self)
            self.metricTypeMap[name] = .summary
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
        quantiles: [Double] = Prometheus.defaultQuantiles) -> PromSummary<T, EmptySummaryLabels>
    {
        return self.createSummary(forType: type, named: name, helpText: helpText, quantiles: quantiles, labels: EmptySummaryLabels.self)
    }
}

/// Prometheus specific errors
public enum PrometheusError: Error {
    /// Thrown when a user tries to retrive
    /// a `PromtheusClient` from `MetricsSystem`
    /// but there was no `PrometheusClient` bootstrapped
    case prometheusFactoryNotBootstrapped(bootstrappedWith: String)
}

