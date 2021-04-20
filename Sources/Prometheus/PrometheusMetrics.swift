import CoreMetrics

private class MetricsCounter: CounterHandler {
    let counter: PromCounter<Int64, DimensionLabels>
    let labels: DimensionLabels?
    
    internal init(counter: PromCounter<Int64, DimensionLabels>, dimensions: [(String, String)]) {
        self.counter = counter
        guard !dimensions.isEmpty else {
            labels = nil
            return
        }
        self.labels = DimensionLabels(dimensions)
    }
    
    func increment(by: Int64) {
        self.counter.inc(by, labels)
    }
    
    func reset() { }
}

private class MetricsGauge: RecorderHandler {
    let gauge: PromGauge<Double, DimensionLabels>
    let labels: DimensionLabels?
    
    internal init(gauge: PromGauge<Double, DimensionLabels>, dimensions: [(String, String)]) {
        self.gauge = gauge
        guard !dimensions.isEmpty else {
            labels = nil
            return
        }
        self.labels = DimensionLabels(dimensions)
    }
    
    func record(_ value: Int64) {
        self.record(value.doubleValue)
    }
    
    func record(_ value: Double) {
        gauge.set(value, labels)
    }
}

private class MetricsHistogram: RecorderHandler {
    let histogram: PromHistogram<Double, DimensionHistogramLabels>
    let labels: DimensionHistogramLabels?
    
    internal init(histogram: PromHistogram<Double, DimensionHistogramLabels>, dimensions: [(String, String)]) {
        self.histogram = histogram
        guard !dimensions.isEmpty else {
            labels = nil
            return
        }
        self.labels = DimensionHistogramLabels(dimensions)
    }
    
    func record(_ value: Int64) {
        histogram.observe(value.doubleValue, labels)
    }
    
    func record(_ value: Double) {
        histogram.observe(value, labels)
    }
}

/// This is a `swift-metrics` timer backed by a Prometheus' `PromHistogram` implementation.
/// This is superior to `Summary` backed timer as `Summary` emits a set of quantiles, which will be impossible to correctly aggregate when one wants to render a percentile for a set of multiple instances.
/// `Histogram` aggregation is possible with some fancy server-side math.
class MetricsHistogramTimer: TimerHandler {
    let histogram: PromHistogram<Int64, DimensionHistogramLabels>
    let labels: DimensionHistogramLabels?
    // this class is a lightweight wrapper around heavy prometheus metric type. This class is not cached and each time
    // created anew. This allows us to use variable timeUnit without locking.
    var timeUnit: TimeUnit?

    init(histogram: PromHistogram<Int64, DimensionHistogramLabels>, dimensions: [(String, String)]) {
        self.histogram = histogram
        if !dimensions.isEmpty {
            self.labels = DimensionHistogramLabels(dimensions)
        } else {
            self.labels = nil
        }
    }

    // this is questionable as display unit here affects how the data is stored, and not how it's observed.
    // should we delete it and tell preferDisplayUnit is not supported?
    func preferDisplayUnit(_ unit: TimeUnit) {
        self.timeUnit = unit
    }

    func recordNanoseconds(_ duration: Int64) {
        // histogram can't be configured with timeUnits, so we have to modify incoming data
        histogram.observe(duration / Int64(timeUnit?.scaleFromNanoseconds ?? 1), labels)
    }
}

private class MetricsSummary: TimerHandler {
    let summary: PromSummary<Int64, DimensionSummaryLabels>
    let labels: DimensionSummaryLabels?
    
    func preferDisplayUnit(_ unit: TimeUnit) {
        self.summary.preferDisplayUnit(unit)
    }
    
    internal init(summary: PromSummary<Int64, DimensionSummaryLabels>, dimensions: [(String, String)]) {
        self.summary = summary
        guard !dimensions.isEmpty else {
            labels = nil
            return
        }
        self.labels = DimensionSummaryLabels(dimensions)
    }
    
    func recordNanoseconds(_ duration: Int64) {
        summary.observe(duration, labels)
    }
}

/// Used to sanitize labels into a format compatible with Prometheus label requirements.
/// Useful when using `PrometheusMetrics` via `SwiftMetrics` with clients which do not necessarily know 
/// about prometheus label formats, and may be using e.g. `.` or upper-case letters in labels (which Prometheus 
/// does not allow).
///
///     let sanitizer: LabelSanitizer = ...
///     let prometheusLabel = sanitizer.sanitize(nonPrometheusLabel)
///
/// By default `PrometheusLabelSanitizer` is used by `PrometheusMetricsFactory`
public protocol LabelSanitizer {
    /// Sanitize the passed in label to a Prometheus accepted value.
    ///
    /// - parameters:
    ///     - label: The created label that needs to be sanitized.
    ///
    /// - returns: A sanitized string that a Prometheus backend will accept.
    func sanitize(_ label: String) -> String
}

/// Default implementation of `LabelSanitizer` that sanitizes any characters not
/// allowed by Prometheus to an underscore (`_`).
///
/// See `https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels` for more info.
public struct PrometheusLabelSanitizer: LabelSanitizer {
    let allowedCharacters = "abcdefghijklmnopqrstuvwxyz0123456789_:"
    
    public init() { }

    public func sanitize(_ label: String) -> String {
        return String(label
            .lowercased()
            .map { (c: Character) -> Character in if allowedCharacters.contains(c) { return c }; return "_" })
    }
}

/// A bridge between PrometheusClient and swift-metrics. Prometheus types don't map perfectly on swift-metrics API,
/// which makes bridge implementation non trivial. This class defines how exactly swift-metrics types should be backed
/// with Prometheus types, e.g. how to sanitize labels, what buckets/quantiles to use for recorder/timer, etc.
public struct PrometheusMetricsFactory: MetricsFactory {

    /// Prometheus client to bridge swift-metrics API to.
    private let client: PrometheusClient

    /// Bridge configuration.
    private let configuration: Configuration

    public init(client: PrometheusClient,
                configuration: Configuration = Configuration()) {
        self.client = client
        self.configuration = configuration
    }

    public func destroyCounter(_ handler: CounterHandler) {
        guard let handler = handler as? MetricsCounter else { return }
        client.removeMetric(handler.counter)
    }
    
    public func destroyRecorder(_ handler: RecorderHandler) {
        if let handler = handler as? MetricsGauge {
            client.removeMetric(handler.gauge)
        }
        if let handler = handler as? MetricsHistogram {
            client.removeMetric(handler.histogram)
        }
    }

    public func destroyTimer(_ handler: TimerHandler) {
        switch self.configuration.timerImplementation._wrapped {
        case .summary:
            guard let handler = handler as? MetricsSummary else { return }
            client.removeMetric(handler.summary)
        case .histogram:
            guard let handler = handler as? MetricsHistogramTimer else { return }
            client.removeMetric(handler.histogram)
        }
    }
    
    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        let label = configuration.labelSanitizer.sanitize(label)
        let createHandler = { (counter: PromCounter) -> CounterHandler in
            return MetricsCounter(counter: counter, dimensions: dimensions)
        }
        if let counter: PromCounter<Int64, DimensionLabels> = client.getMetricInstance(with: label, andType: .counter) {
            return createHandler(counter)
        }
        return createHandler(client.createCounter(forType: Int64.self, named: label, withLabelType: DimensionLabels.self))
    }
    
    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        let label = configuration.labelSanitizer.sanitize(label)
        return aggregate ? makeHistogram(label: label, dimensions: dimensions) : makeGauge(label: label, dimensions: dimensions)
    }
    
    private func makeGauge(label: String, dimensions: [(String, String)]) -> RecorderHandler {
        let label = configuration.labelSanitizer.sanitize(label)
        let createHandler = { (gauge: PromGauge) -> RecorderHandler in
            return MetricsGauge(gauge: gauge, dimensions: dimensions)
        }
        if let gauge: PromGauge<Double, DimensionLabels> = client.getMetricInstance(with: label, andType: .gauge) {
            return createHandler(gauge)
        }
        return createHandler(client.createGauge(forType: Double.self, named: label, withLabelType: DimensionLabels.self))
    }
    
    private func makeHistogram(label: String, dimensions: [(String, String)]) -> RecorderHandler {
        let label = configuration.labelSanitizer.sanitize(label)
        let createHandler = { (histogram: PromHistogram) -> RecorderHandler in
            return MetricsHistogram(histogram: histogram, dimensions: dimensions)
        }
        if let histogram: PromHistogram<Double, DimensionHistogramLabels> = client.getMetricInstance(with: label, andType: .histogram) {
            return createHandler(histogram)
        }
        return createHandler(client.createHistogram(forType: Double.self, named: label, labels: DimensionHistogramLabels.self))
    }
    
    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        switch configuration.timerImplementation._wrapped {
        case .summary(let quantiles):
            return self.makeSummaryTimer(label: label, dimensions: dimensions, quantiles: quantiles)
        case .histogram(let buckets):
            return self.makeHistogramTimer(label: label, dimensions: dimensions, buckets: buckets)
        }
    }

    /// There's two different ways to back swift-api `Timer` with Prometheus classes.
    /// This method creates `Summary` backed timer implementation
    private func makeSummaryTimer(label: String, dimensions: [(String, String)], quantiles: [Double]) -> TimerHandler {
        let label = configuration.labelSanitizer.sanitize(label)
        let createHandler = { (summary: PromSummary) -> TimerHandler in
            return MetricsSummary(summary: summary, dimensions: dimensions)
        }
        if let summary: PromSummary<Int64, DimensionSummaryLabels> = client.getMetricInstance(with: label, andType: .summary) {
            return createHandler(summary)
        }
        return createHandler(client.createSummary(forType: Int64.self, named: label, quantiles: quantiles, labels: DimensionSummaryLabels.self))
    }

    /// There's two different ways to back swift-api `Timer` with Prometheus classes.
    /// This method creates `Histogram` backed timer implementation
    private func makeHistogramTimer(label: String, dimensions: [(String, String)], buckets: Buckets) -> TimerHandler {
        let createHandler = { (histogram: PromHistogram) -> TimerHandler in
            MetricsHistogramTimer(histogram: histogram, dimensions: dimensions)
        }
        // PromHistogram should be reused when created for the same label, so we try to look it up
        if let histogram: PromHistogram<Int64, DimensionHistogramLabels> = client.getMetricInstance(with: label, andType: .histogram) {
            return createHandler(histogram)
        }
        return createHandler(client.createHistogram(forType: Int64.self, named: label, buckets: buckets, labels: DimensionHistogramLabels.self))
    }
}

public extension MetricsSystem {
    /// Get the bootstrapped `MetricsSystem` as `PrometheusClient`
    ///
    /// - Returns: `PrometheusClient` used to bootstrap `MetricsSystem`
    /// - Throws: `PrometheusError.PrometheusFactoryNotBootstrapped`
    ///             if no `PrometheusClient` was used to bootstrap `MetricsSystem`
    static func prometheus() throws -> PrometheusClient {
        guard let prom = self.factory as? PrometheusClient else {
            throw PrometheusError.prometheusFactoryNotBootstrapped(bootstrappedWith: "\(self.factory)")
        }
        return prom
    }
}

// MARK: - Labels

/// A generic `String` based `CodingKey` implementation.
private struct StringCodingKey: CodingKey {
    /// `CodingKey` conformance.
    public var stringValue: String
    
    /// `CodingKey` conformance.
    public var intValue: Int? {
        return Int(self.stringValue)
    }
    
    /// Creates a new `StringCodingKey`.
    public init(_ string: String) {
        self.stringValue = string
    }
    
    /// `CodingKey` conformance.
    public init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    /// `CodingKey` conformance.
    public init(intValue: Int) {
        self.stringValue = intValue.description
    }
}



/// Helper for dimensions
public struct DimensionLabels: MetricLabels {
    let dimensions: [(String, String)]
    
    public init() {
        self.dimensions = []
    }
    
    public init(_ dimensions: [(String, String)]) {
        self.dimensions = dimensions
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
    }
    
    fileprivate var identifiers: String {
        return dimensions.map { $0.0 }.joined(separator: "-")
    }
    
    public static func == (lhs: DimensionLabels, rhs: DimensionLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"}
    }
}

/// Helper for dimensions
/// swift-metrics api doesn't allow setting buckets explicitly.
/// If default buckets don't fit, this Labels implementation is a nice default to create Prometheus metric types wtih
public struct DimensionHistogramLabels: HistogramLabels {
    /// Bucket
    public var le: String
    /// Dimensions
    let dimensions: [(String, String)]
    
    /// Empty init
    public init() {
        self.le = ""
        self.dimensions = []
    }
    
    /// Init with dimensions
    public init(_ dimensions: [(String, String)]) {
        self.le = ""
        self.dimensions = dimensions
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
        try container.encode(le, forKey: .init("le"))
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
        hasher.combine(le)
    }
    
    fileprivate var identifiers: String {
        return dimensions.map { $0.0 }.joined(separator: "-")
    }
    
    public static func == (lhs: DimensionHistogramLabels, rhs: DimensionHistogramLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"} && rhs.le == lhs.le
    }
}

/// Helper for dimensions
public struct DimensionSummaryLabels: SummaryLabels {
    /// Quantile
    public var quantile: String
    /// Dimensions
    let dimensions: [(String, String)]
    
    /// Empty init
    public init() {
        self.quantile = ""
        self.dimensions = []
    }
    
    /// Init with dimensions
    public init(_ dimensions: [(String, String)]) {
        self.quantile = ""
        self.dimensions = dimensions
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
        try container.encode(quantile, forKey: .init("quantile"))
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
        hasher.combine(quantile)
    }
    
    fileprivate var identifiers: String {
        return dimensions.map { $0.0 }.joined(separator: "-")
    }
    
    public static func == (lhs: DimensionSummaryLabels, rhs: DimensionSummaryLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"} && rhs.quantile == lhs.quantile
    }
}
