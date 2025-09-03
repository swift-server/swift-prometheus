# Practical Example with Labels Deep Dive

Create, register, update, and expose metrics for Prometheus.

## Overview

Create multiple collectors that are associated with a specific `PrometheusCollectorRegistry()` instance.

```swift
// Create an instance of `PrometheusCollectorRegistry`
let registry = PrometheusCollectorRegistry()

// Create a family of labeled Counters with different label sets
let httpRequestsDescriptor = MetricNameDescriptor(
    namespace: "myapp",
    subsystem: "http",
    metricName: "requests",
    unitName: "total",
    helpText: "Total HTTP requests"
)

let httpRequestsGet = registry.makeCounter(
    descriptor: httpRequestsDescriptor,
    labels: [("method", "GET"), ("status", "200")]
)

let httpRequestsPost = registry.makeCounter(
    descriptor: httpRequestsDescriptor,
    labels: [("method", "POST"), ("status", "201")]
)

let httpRequestsError = registry.makeCounter(
    descriptor: httpRequestsDescriptor,
    labels: [("method", "GET"), ("status", "500"), ("endpoint", "/api/users")]
)

// Create an unlabeled Counter
let totalErrorsCounter = registry.makeCounter(descriptor: MetricNameDescriptor(
    namespace: "myapp",
    subsystem: "system",
    metricName: "errors",
    unitName: "total",
    helpText: "Total system errors"
))

// Create a DurationHistogram metric
let responseTimeDescriptor = MetricNameDescriptor(
    namespace: "myapp",
    subsystem: "http",
    metricName: "request_duration",
    unitName: "seconds",
    helpText: "HTTP request duration in seconds"
)

let responseTime = registry.makeDurationHistogram(
    descriptor: responseTimeDescriptor,
    buckets: [.milliseconds(10), .milliseconds(100), .seconds(1)]
)

// Create a Gauge metric
let memoryDescriptor = MetricNameDescriptor(
    namespace: "myapp",
    subsystem: "system",
    metricName: "memory_usage",
    unitName: "bytes",
    helpText: "Current memory usage in bytes"
)

let memoryUsage = registry.makeGauge(descriptor: memoryDescriptor)

// Create a Gauge metric via passing the metric name and help directly
let activeConnections = registry.makeGauge(
    name: "myapp_http_connections_active",
    help: "Currently active HTTP connections"
)

// Simulate some metrics
httpRequestsGet.increment(by: 5.0)
httpRequestsPost.increment(by: 2.0)
httpRequestsError.increment()
totalErrorsCounter.increment(by: 3.0)
responseTime.record(.milliseconds(150))
memoryUsage.set(Double(1024 * 1024 * 128)) // 134,217,728 bytes (128MB)
activeConnections.set(42.0)

// Emit all metrics (thread-safe option)
let output = registry.emitToString()
print(output)
```

```sh
# HELP myapp_http_connections_active Currently active HTTP connections
# TYPE myapp_http_connections_active gauge
myapp_http_connections_active 42.0
# HELP myapp_http_requests_total Total HTTP requests
# TYPE myapp_http_requests_total counter
myapp_http_requests_total{method="GET",status="200"} 5.0
myapp_http_requests_total{method="POST",status="201"} 2.0
myapp_http_requests_total{method="GET",status="500",endpoint="/api/users"} 1
# HELP myapp_system_errors_total Total system errors
# TYPE myapp_system_errors_total counter
myapp_system_errors_total 3.0
# HELP myapp_http_request_duration_seconds HTTP request duration in seconds
# TYPE myapp_http_request_duration_seconds histogram
myapp_http_request_duration_seconds_bucket{le="0.01"} 0
myapp_http_request_duration_seconds_bucket{le="0.1"} 0
myapp_http_request_duration_seconds_bucket{le="1.0"} 1
myapp_http_request_duration_seconds_bucket{le="+Inf"} 1
myapp_http_request_duration_seconds_sum 0.15
myapp_http_request_duration_seconds_count 1
# HELP myapp_system_memory_usage_bytes Current memory usage in bytes
# TYPE myapp_system_memory_usage_bytes gauge
myapp_system_memory_usage_bytes 134217728.0
```

### Notice how:

*Metadata Deduplication:*
- Each metric name gets exactly one `# HELP` and `# TYPE` line (before the metric output), regardless of how many label variations exist.

*Label Flexibility:*
- The same metric name `myapp_http_requests_total` supports different label structures:
  - `{method="GET",status="200"}` (2 labels)
  - `{method="POST",status="201"}` (2 labels) 
  - `{method="GET",status="500",endpoint="/api/users"}` (3 labels)
- Each unique combination of metric name and label set (as determined by hashing each key and value together) generates a single time series.

*Metric Type Behaviors:*
- *Counter*: `myapp_http_requests_total` and `myapp_system_errors_total` - monotonically increasing values.
- *Histogram*: `myapp_http_request_duration_seconds` - automatically generates multiple time series (`_bucket`, `_sum`, `_count`).
- *Gauge*: `myapp_system_memory_usage_bytes` and `myapp_http_connections_active` - can increase or decrease.

*Naming Conventions:*
- Proper namespacing: `myapp` prefix identifies the application.
- Descriptive subsystems: `http`, `system` group related metrics.
- Unit suffixes: `total`, `seconds`, `bytes`, `active` clarify what's being measured.

*Prometheus Compliance:*
- Metric names, label names, and `# HELP` text are validated against Prometheus character allowlists.
- Different label names and structures are allowed for the same metric name; however, cannot mix labeled and unlabeled metrics with the same metric name.
- Must use consistent metric types, help text, and histogram buckets for the same metric name.

*Known Limitations:*
- Prometheus converts all metrics to floating-point types, which can cause precision loss. For example, Counters designed for `UInt64` values or Gauges capturing nanosecond timestamps will lose precision. In such cases, consider alternative frameworks or solutions.

*Thread-safe through multiple mechanisms:*
- Metric value updates are based on atomic operations.
- Export functions like `emitToBuffer()` and `emitToString()` use internal locking and conform to Swift [Sendable](https://developer.apple.com/documentation/Swift/Sendable).
- Lower-level export via `emit(into:)` is thread-safe due to Swift's `inout` [exclusivity](https://www.swift.org/blog/swift-5-exclusivity/) guarantees, with the compiler preventing concurrent access through warnings (Swift 5) or errors (Swift 6 [strict concurrency](https://developer.apple.com/documentation/swift/adoptingswift6) mode).

✅ *Correct Labels Usage:*

```swift
// All labeled with same structure
let counter1 = registry.makeCounter(name: "requests", labels: [("method", "GET")])
let counter2 = registry.makeCounter(name: "requests", labels: [("method", "POST")])
let counter3 = registry.makeCounter(name: "requests", labels: [("method", "PUT")])

// Different label names are also allowed
let counter4 = registry.makeCounter(name: "requests", labels: [("endpoint", "/api")])
let counter5 = registry.makeCounter(name: "requests", labels: [("status", "200")])

// Different numbers of labels are fine too
let counter6 = registry.makeCounter(name: "requests", labels: [("method", "DELETE"), ("endpoint", "/users"), ("region", "us-east")])
```

❌ *Incorrect Labels Usage (Will Crash):*

```swift
// This will crash - mixing labeled and unlabeled
let counter1 = registry.makeCounter(name: "requests") // unlabeled
let counter2 = registry.makeCounter(name: "requests", labels: [("method", "GET")]) // 💥 crash

// This will crash - different metric types
let counter = registry.makeCounter(name: "requests")
let gauge = registry.makeGauge(name: "requests") // 💥 crash

// This will crash - different help text for same metric name
let counter1 = registry.makeCounter(name: "requests", help: "HTTP requests")
let counter2 = registry.makeCounter(name: "requests", help: "API requests") // 💥 crash

// This will crash - different buckets for same histogram name
let hist1 = registry.makeDurationHistogram(name: "duration", buckets: [.seconds(1)])
let hist2 = registry.makeDurationHistogram(name: "duration", buckets: [.seconds(2)]) // 💥 crash
```

⚠️ *Discouraged Practices (Will Work But Not Recommended):*

```swift
// ❌ Don't use reserved Prometheus label names
let badCounter1 = registry.makeCounter(name: "requests", labels: [("le", "100")]) // "le" is reserved for histograms
let badCounter2 = registry.makeCounter(name: "requests", labels: [("quantile", "0.95")]) // "quantile" is reserved for summaries

// ❌ Don't use metric suffixes as label values
let badCounter3 = registry.makeCounter(name: "requests", labels: [("type", "total")]) // Use _total suffix instead
let badCounter4 = registry.makeCounter(name: "requests", labels: [("aggregation", "sum")]) // Use _total suffix instead
let badCounter5 = registry.makeCounter(name: "requests", labels: [("aggregation", "count")]) // Use _total suffix instead

// ✅ Better alternatives
let goodCounter1 = registry.makeCounter(name: "requests_total", labels: [("method", "GET")]) // Descriptive labels
let goodCounter2 = registry.makeCounter(name: "requests_total", labels: [("endpoint", "/api/users")]) // Meaningful dimensions
```

*Additional Notes*:

Above, we demonstrated the Prometheus’s proper approach. However, you can also use [Swift Metrics](doc:swift-metrics) as a backend for this library via `PrometheusMetricsFactory`.

> Note: The naming between Prometheus and Swift-Metrics may be confusing. Swift Metrics calls a 
> metric's name its label and they call a metric's labels dimensions. In this article, when we 
> refer to labels, we mean the additional properties that can be added to a metrics name.
>
> | Framework     | Metric name | Additional infos |
> |---------------|-------------|------------------|
> | swift-metrics | `label`     | `dimensions`     |
> | Prometheus    | `name`      | `labels`         |

### References

- Prometheus [Docs - Overview][prometheus-docs]
- Prometheus [Instrumentation Best Practices - Use Labels][prometheus-use-labels]
- Prometheus [Naming Best Practices][prometheus-naming]
- Prometheus [Client Library Guidelines][prometheus-client-libs]
- Prometheus [Exporter Guidelines][prometheus-exporters]
- Prometheus [Exposition Format][prometheus-exposition]

[prometheus-docs]: https://prometheus.io/docs/introduction/overview/
[prometheus-use-labels]: https://prometheus.io/docs/practices/instrumentation/#use-labels
[prometheus-naming]: https://prometheus.io/docs/practices/naming/
[prometheus-client-libs]: https://prometheus.io/docs/instrumenting/writing_clientlibs/
[prometheus-exporters]: https://prometheus.io/docs/instrumenting/writing_exporters/
[prometheus-exposition]: https://prometheus.io/docs/instrumenting/exposition_formats/
