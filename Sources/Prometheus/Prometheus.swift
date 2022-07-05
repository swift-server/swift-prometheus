import NIOConcurrencyHelpers
import NIO
import Foundation

/// Prometheus class
///
/// See https://prometheus.io/docs/introduction/overview/
public class PrometheusClient {

    /// Metrics tracked by this Prometheus instance
    private var metrics: [String: PromMetric]
    
    /// Lock used for thread safety
    private let lock: Lock
    
    /// Used for the pushgateway, necessary property, so that the timer doesn't get deinitialised
    private var timer: RepeatingTimer?
    
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

            let counter = PromCounter<T>(name, helpText, initialValue, self)
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

            let gauge = PromGauge<T>(name, helpText, initialValue, self)
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

            let histogram = PromHistogram<T>(name, helpText, buckets, self)
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
            let summary = PromSummary<T>(name, helpText, capacity, quantiles, self)
            let oldInstrument = self.metrics.updateValue(summary, forKey: name)
            precondition(oldInstrument == nil, "Label \(oldInstrument!.name) is already associated with a \(oldInstrument!._type).")
            return summary
        }
    }
}

// MARK: - PushGateway
extension PrometheusClient {
    
    /// Sets up a repeated event which pushes the metrics to a PrometheusPushGateway instance
    ///
    /// - Parameters:
    ///     - shouldUseHttps: The protocol that should be used for the connection
    ///     - host: The host where the pushgateway is located
    ///     - port: Optionally the port where the pushgateway is located
    ///     - jobName: The job name, under which the data is submitted
    ///     - pushInterval: The interval between each push
    ///     - shouldIncludeKeepAliveHeader: Shows whether the connection should be kept alive to avoid overhead from HTTP Handshake. True by default as it saves resources when the pushInterval is small.
    ///
    /// - Returns: Summary instance
    public func pushToGateway(shouldUseHttps: Bool = false, host: String, port: Int? = nil, jobName: String, shouldIncludeKeepAliveHeader: Bool = true, pushInterval: Double = 5.0) {
        
        guard var request = generateRequestWithHeaders(shouldUseHttps: shouldUseHttps, host: host, port: port, jobName: jobName, shouldIncludeKeepAliveHeader: shouldIncludeKeepAliveHeader) else {
            print("Couldn't generate HTTP Headers")
            return
        }
        
        // Semaphore necessary to avoid race conditions in the case of a slow task execution.
        let semaphore = DispatchSemaphore (value: 0)
        
        let closure: (String) -> () = { parameters in
            
            let postData = parameters.data(using: .utf8)
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
              guard let _ = data else {
                print(String(describing: error))
                semaphore.signal()
                return
              }
                
              semaphore.signal()
            }

            task.resume()
            semaphore.wait()
        }
        
        setupTimer(timerInterval: pushInterval, for: closure)
    }
    
    /// Generates a request with an empty body and the provided header data
    ///
    /// - Parameters:
    ///     - shouldUseHttps: The protocol that should be used for the connection
    ///     - host: The host where the pushgateway is located
    ///     - port: Optionally the port where the pushgateway is located
    ///     - jobName: The job name, under which the data is submitted
    ///     - shouldIncludeKeepAliveHeader: Shows whether the connection should be kept alive to avoid overhead from HTTP Handshake.
    ///
    /// - Returns: The generated request
    private func generateRequestWithHeaders(shouldUseHttps: Bool, host: String, port: Int?, jobName: String, shouldIncludeKeepAliveHeader: Bool) -> URLRequest? {
        var address = host
        if let port = port {
            address.append(contentsOf: ":\(port)")
        }
        
        let connectionType = shouldUseHttps ? "https" : "http"
        
        let urlString = "\(connectionType)://\(address)/metrics/job/\(jobName)"
        
        guard let url = URL(string: urlString) else {
            print("PushGatewayUrlString invalid: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url, timeoutInterval: Double.infinity)
        
        request.addValue("text/plain", forHTTPHeaderField: "Content-Type")
        
        if shouldIncludeKeepAliveHeader {
            request.addValue("Keep-Alive", forHTTPHeaderField: "Connection")
        }
        
        request.httpMethod = "POST"
        
        return request
    }
    
    /// Creates a repeating timer which executes the closure block every pushInterval seconds.
    ///
    /// - Parameters:
    ///     - pushInterval: The interval between each closure trigger.
    ///     - for: The closure to be triggered.
    private func setupTimer(timerInterval: Double, for closure: @escaping (String) -> ()) {
        timer = RepeatingTimer(timeInterval: timerInterval)
        
        guard let timer = timer else {
            return
        }
        
        timer.eventHandler = { [weak self] in
            self?.collect(closure)
        }
        timer.resume()
    }
    
    /// Removes the repeated event, which submits data to the pushgateway
    public func tearDownPushToGateway() {
        timer = nil
    }
}

/// Prometheus specific errors
public enum PrometheusError: Error {
    /// Thrown when a user tries to retrieve
    /// a `PrometheusClient` from `MetricsSystem`
    /// but there was no `PrometheusClient` bootstrapped
    case prometheusFactoryNotBootstrapped(bootstrappedWith: String)
}
