import NIOConcurrencyHelpers
import NIO

/// Prometheus class
///
/// See https://prometheus.io/docs/introduction/overview/
public class PrometheusClient {

    /// Metrics tracked by this Prometheus instance
    private var metrics: [String: PromMetric]
    
    /// Lock used for thread safety
    private let lock: Lock
    
    /// Create a PrometheusClient instance
    public init() {
        self.metrics = [:]
        self.lock = Lock()
    }
    
    // MARK: - Collection

#if swift(>=5.4)
    /// Creates prometheus formatted metrics
    ///
    /// - returns: A newline separated string with metrics for all Metrics this PrometheusClient handles
    @available(macOS 10.15.0, *)
    public func collect() async -> String {
        let metrics = self.lock.withLock { self.metrics }
        return metrics.isEmpty ? "" : "\(metrics.values.map { $0.collect() }.joined(separator: "\n"))\n"
    }
#endif

    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - succeed: Closure that will be called with a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(_ succeed: (String) -> ()) {
        let metrics = self.lock.withLock { self.metrics }
        succeed(metrics.isEmpty ? "" : "\(metrics.values.map { $0.collect() }.joined(separator: "\n"))\n")
    }
    
    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - promise: Promise that will succeed with a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(into promise: EventLoopPromise<String>) {
        collect(promise.succeed)
    }

#if swift(>=5.4)
    /// Creates prometheus formatted metrics
    ///
    /// - returns: A `ByteBuffer` containing a newline separated string with metrics for all Metrics this PrometheusClient handles
    @available(macOS 10.15.0, *)
    public func collect() async -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        let metrics = self.lock.withLock { self.metrics }
        metrics.values.forEach {
            $0.collect(into: &buffer)
            buffer.writeString("\n")
        }
        return buffer
    }
#endif

    /// Creates prometheus formatted metrics
    ///
    /// - Parameters:
    ///     - succeed: Closure that will be called with a `ByteBuffer` containing a newline separated string with metrics for all Metrics this PrometheusClient handles
    public func collect(_ succeed: (ByteBuffer) -> ()) {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        let metrics = self.lock.withLock { self.metrics }
        metrics.values.forEach {
            $0.collect(into: &buffer)
            buffer.writeString("\n")
        }
        succeed(buffer)
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
            self.metrics.removeValue(forKey: metric.name)
        }
    }
    
    public func getMetricInstance<Metric>(with name: String, andType type: PromMetricType) -> Metric? where Metric: PromMetric {
        return lock.withLock {
            self._getMetricInstance(with: name, andType: type)
        }
    }
    
    private func _getMetricInstance<Metric>(with name: String, andType type: PromMetricType) -> Metric? where Metric: PromMetric {
        if let metric = self.metrics[name], metric._type == type {
            return metric as? Metric
        } else {
            return nil
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
            if let cachedCounter: PromCounter<T, U> = self._getMetricInstance(with: name, andType: .counter) {
                return cachedCounter
            }

            let counter = PromCounter<T, U>(name, helpText, initialValue, self)
            let oldInstrument = self.metrics.updateValue(counter, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
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
            if let cachedGauge: PromGauge<T, U> = self._getMetricInstance(with: name, andType: .gauge) {
                return cachedGauge
            }

            let gauge = PromGauge<T, U>(name, helpText, initialValue, self)
            let oldInstrument = self.metrics.updateValue(gauge, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
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
        return self.lock.withLock {
            if let cachedHistogram: PromHistogram<T, U> = self._getMetricInstance(with: name, andType: .histogram) {
                return cachedHistogram
            }

            let histogram = PromHistogram<T, U>(name, helpText, U(), buckets, self)
            let oldInstrument = self.metrics.updateValue(histogram, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
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
    ///     - capacity: Number of observations to keep for calculating quantiles
    ///     - quantiles: Quantiles to calculate
    ///     - labels: Labels to give this summary. Can be left out to default to no labels
    ///
    /// - Returns: Summary instance
    public func createSummary<T: Numeric, U: SummaryLabels>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        capacity: Int = Prometheus.defaultSummaryCapacity,
        quantiles: [Double] = Prometheus.defaultQuantiles,
        labels: U.Type) -> PromSummary<T, U>
    {
        return self.lock.withLock {
            if let cachedSummary: PromSummary<T, U> = self._getMetricInstance(with: name, andType: .summary) {
                return cachedSummary
            }
            let summary = PromSummary<T, U>(name, helpText, U(), capacity, quantiles, self)
            let oldInstrument = self.metrics.updateValue(summary, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
            return summary
        }
    }
    
    /// Creates a summary with the given values
    ///
    /// - Parameters:
    ///     - type: The type the summary will observe
    ///     - name: Name of the summary
    ///     - helpText: Help text for the summary. Usually a short description
    ///     - quantiles: Quantiles to calculate
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
    /// Thrown when a user tries to retrieve
    /// a `PrometheusClient` from `MetricsSystem`
    /// but there was no `PrometheusClient` bootstrapped
    case prometheusFactoryNotBootstrapped(bootstrappedWith: String)
}
