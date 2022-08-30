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

#if swift(>=5.5)
    /// Creates prometheus formatted metrics
    ///
    /// - returns: A newline separated string with metrics for all Metrics this PrometheusClient handles
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func collect() async -> String {
        let metrics = self.lock.withLock { self.metrics }
        let task = Task {
            return metrics.isEmpty ? "" : "\(metrics.values.map { $0.collect() }.joined(separator: "\n"))\n"
        }
        return await task.value
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

#if swift(>=5.5)
    /// Creates prometheus formatted metrics
    ///
    /// - returns: A `ByteBuffer` containing a newline separated string with metrics for all Metrics this PrometheusClient handles
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func collect() async -> ByteBuffer {
        let metrics = self.lock.withLock { self.metrics }
        let task = Task { () -> ByteBuffer in
            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            metrics.values.forEach {
                $0.collect(into: &buffer)
                buffer.writeString("\n")
            }
            return buffer
        }
        return await task.value
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
    ///
    /// - Returns: Counter instance
    public func createCounter<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        initialValue: T = 0) -> PromCounter<T>
    {
        return self.lock.withLock {
            if let cachedCounter: PromCounter<T> = self._getMetricInstance(with: name, andType: .counter) {
                return cachedCounter
            }

            let counter = PromCounter<T>(name, helpText, initialValue)
            let oldInstrument = self.metrics.updateValue(counter, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
            return counter
        }
    }
    
    // MARK: - Gauge
    
    /// Creates a gauge with the given values
    ///
    /// - Parameters:
    ///     - type: Type the gauge will hold
    ///     - name: Name of the gauge
    ///     - helpText: Help text for the gauge. Usually a short description
    ///     - initialValue: An initial value to set the gauge to, defaults to 0
    ///
    /// - Returns: Gauge instance
    public func createGauge<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        initialValue: T = 0) -> PromGauge<T>
    {
        return self.lock.withLock {
            if let cachedGauge: PromGauge<T> = self._getMetricInstance(with: name, andType: .gauge) {
                return cachedGauge
            }

            let gauge = PromGauge<T>(name, helpText, initialValue)
            let oldInstrument = self.metrics.updateValue(gauge, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
            return gauge
        }
    }
    
    // MARK: - Histogram
    
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
        buckets: Buckets = .defaultBuckets) -> PromHistogram<T>
    {
        return self.lock.withLock {
            if let cachedHistogram: PromHistogram<T> = self._getMetricInstance(with: name, andType: .histogram) {
                return cachedHistogram
            }

            let histogram = PromHistogram<T>(name, helpText, buckets)
            let oldInstrument = self.metrics.updateValue(histogram, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
            return histogram
        }
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
    ///
    /// - Returns: Summary instance
    public func createSummary<T: Numeric>(
        forType type: T.Type,
        named name: String,
        helpText: String? = nil,
        capacity: Int = Prometheus.defaultSummaryCapacity,
        quantiles: [Double] = Prometheus.defaultQuantiles) -> PromSummary<T>
    {
        return self.lock.withLock {
            if let cachedSummary: PromSummary<T> = self._getMetricInstance(with: name, andType: .summary) {
                return cachedSummary
            }
            let summary = PromSummary<T>(name, helpText, capacity, quantiles)
            let oldInstrument = self.metrics.updateValue(summary, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
            return summary
        }
    }
}

/// Prometheus specific errors
public enum PrometheusError: Error {
    /// Thrown when a user tries to retrieve
    /// a `PrometheusClient` from `MetricsSystem`
    /// but there was no `PrometheusClient` bootstrapped
    case prometheusFactoryNotBootstrapped(bootstrappedWith: String)
}
