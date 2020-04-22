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
/// By default `PrometheusLabelSanitizer` is used by `PrometheusClient`
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

extension PrometheusClient: MetricsFactory {
    public func destroyCounter(_ handler: CounterHandler) {
        guard let handler = handler as? MetricsCounter else { return }
        self.removeMetric(handler.counter)
    }
    
    public func destroyRecorder(_ handler: RecorderHandler) {
        if let handler = handler as? MetricsGauge {
            self.removeMetric(handler.gauge)
        }
        if let handler = handler as? MetricsHistogram {
            self.removeMetric(handler.histogram)
        }
    }
    
    public func destroyTimer(_ handler: TimerHandler) {
        guard let handler = handler as? MetricsSummary else { return }
        self.removeMetric(handler.summary)
    }
    
    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        let label = self.sanitizer.sanitize(label)
        let createHandler = { (counter: PromCounter) -> CounterHandler in
            return MetricsCounter(counter: counter, dimensions: dimensions)
        }
        if let counter: PromCounter<Int64, DimensionLabels> = self.getMetricInstance(with: label, andType: .counter) {
            return createHandler(counter)
        }
        return createHandler(self.createCounter(forType: Int64.self, named: label, withLabelType: DimensionLabels.self))
    }
    
    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        let label = self.sanitizer.sanitize(label)
        return aggregate ? makeHistogram(label: label, dimensions: dimensions) : makeGauge(label: label, dimensions: dimensions)
    }
    
    private func makeGauge(label: String, dimensions: [(String, String)]) -> RecorderHandler {
        let label = self.sanitizer.sanitize(label)
        let createHandler = { (gauge: PromGauge) -> RecorderHandler in
            return MetricsGauge(gauge: gauge, dimensions: dimensions)
        }
        if let gauge: PromGauge<Double, DimensionLabels> = self.getMetricInstance(with: label, andType: .gauge) {
            return createHandler(gauge)
        }
        return createHandler(createGauge(forType: Double.self, named: label, withLabelType: DimensionLabels.self))
    }
    
    private func makeHistogram(label: String, dimensions: [(String, String)]) -> RecorderHandler {
        let label = self.sanitizer.sanitize(label)
        let createHandler = { (histogram: PromHistogram) -> RecorderHandler in
            return MetricsHistogram(histogram: histogram, dimensions: dimensions)
        }
        if let histogram: PromHistogram<Double, DimensionHistogramLabels> = self.getMetricInstance(with: label, andType: .histogram) {
            return createHandler(histogram)
        }
        return createHandler(createHistogram(forType: Double.self, named: label, labels: DimensionHistogramLabels.self))
    }
    
    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        let label = self.sanitizer.sanitize(label)
        let createHandler = { (summary: PromSummary) -> TimerHandler in
            return MetricsSummary(summary: summary, dimensions: dimensions)
        }
        if let summary: PromSummary<Int64, DimensionSummaryLabels> = self.getMetricInstance(with: label, andType: .summary) {
            return createHandler(summary)
        }
        return createHandler(createSummary(forType: Int64.self, named: label, labels: DimensionSummaryLabels.self))
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
private struct DimensionLabels: MetricLabels {
    let dimensions: [(String, String)]
    
    init() {
        self.dimensions = []
    }
    
    init(_ dimensions: [(String, String)]) {
        self.dimensions = dimensions
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
    }
    
    fileprivate var identifiers: String {
        return dimensions.map { $0.0 }.joined(separator: "-")
    }
    
    static func == (lhs: DimensionLabels, rhs: DimensionLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"}
    }
}

/// Helper for dimensions
private struct DimensionHistogramLabels: HistogramLabels {
    /// Bucket
    var le: String
    /// Dimensions
    let dimensions: [(String, String)]
    
    /// Empty init
    init() {
        self.le = ""
        self.dimensions = []
    }
    
    /// Init with dimensions
    init(_ dimensions: [(String, String)]) {
        self.le = ""
        self.dimensions = dimensions
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
        try container.encode(le, forKey: .init("le"))
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
        hasher.combine(le)
    }
    
    fileprivate var identifiers: String {
        return dimensions.map { $0.0 }.joined(separator: "-")
    }
    
    static func == (lhs: DimensionHistogramLabels, rhs: DimensionHistogramLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"} && rhs.le == lhs.le
    }
}

/// Helper for dimensions
private struct DimensionSummaryLabels: SummaryLabels {
    /// Quantile
    var quantile: String
    /// Dimensions
    let dimensions: [(String, String)]
    
    /// Empty init
    init() {
        self.quantile = ""
        self.dimensions = []
    }
    
    /// Init with dimensions
    init(_ dimensions: [(String, String)]) {
        self.quantile = ""
        self.dimensions = dimensions
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
        try container.encode(quantile, forKey: .init("quantile"))
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
        hasher.combine(quantile)
    }
    
    fileprivate var identifiers: String {
        return dimensions.map { $0.0 }.joined(separator: "-")
    }
    
    static func == (lhs: DimensionSummaryLabels, rhs: DimensionSummaryLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"} && rhs.quantile == lhs.quantile
    }
}
