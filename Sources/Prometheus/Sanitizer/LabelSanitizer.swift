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