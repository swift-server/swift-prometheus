public struct PrometheusMetricsConfiguration {
    /// Sanitizers used to clean up label values provided through
    /// swift-metrics.
    public var labelSanitizer: LabelSanitizer

    /// This parameter will define what implementation will be used for bridging `swift-metrics` to Prometheus types.
    public var timerImplementation: PrometheusTimerImplementation

    /// Default buckets for `Recorder` with aggregation.
    public var defaultHistogramBuckets: Buckets

    public init(labelSanitizer: LabelSanitizer = PrometheusLabelSanitizer(),
                timerImplementation: PrometheusTimerImplementation = .summary(),
                defaultHistogramBuckets: Buckets = .defaultBuckets) {
        self.labelSanitizer = labelSanitizer
        self.timerImplementation = timerImplementation
        self.defaultHistogramBuckets = defaultHistogramBuckets
    }
}
