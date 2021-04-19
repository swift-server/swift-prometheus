extension PrometheusMetricsFactory {

    public struct TimerImplementation {
        enum _Wrapped {
            case summary(defaultQuantiles: [Double])
            case histogram(defaultBuckets: Buckets)
        }

        var _wrapped: _Wrapped

        private init(_ wrapped: _Wrapped) {
            self._wrapped = wrapped
        }

        public static func summary(defaultQuantiles: [Double] = Prometheus.defaultQuantiles) -> TimerImplementation {
            TimerImplementation(.summary(defaultQuantiles: defaultQuantiles))
        }

        public static func histogram(defaultBuckets: Buckets = Buckets.defaultBuckets) -> TimerImplementation {
            TimerImplementation(.histogram(defaultBuckets: defaultBuckets))
        }
    }


    /// Configuration for PrometheusClient to swift-metrics api bridge.
    public struct Configuration {
        /// Sanitizers used to clean up label values provided through
        /// swift-metrics.
        public var labelSanitizer: LabelSanitizer

        /// This parameter will define what implementation will be used for bridging `swift-metrics` to Prometheus types.
        public var timerImplementation: PrometheusMetricsFactory.TimerImplementation

        /// Default buckets for `Recorder` with aggregation.
        public var defaultHistogramBuckets: Buckets

        public init(labelSanitizer: LabelSanitizer = PrometheusLabelSanitizer(),
                    timerImplementation: PrometheusMetricsFactory.TimerImplementation = .summary(),
                    defaultHistogramBuckets: Buckets = .defaultBuckets) {
            self.labelSanitizer = labelSanitizer
            self.timerImplementation = timerImplementation
            self.defaultHistogramBuckets = defaultHistogramBuckets
        }
    }
}