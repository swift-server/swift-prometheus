# ``Prometheus``

A prometheus client library for Swift.

## Overview

``Prometheus`` supports creating ``Counter``s, ``Gauge``s and ``Histogram``s, updating metric values, and exposing their values in the Prometheus text format.

#### Key Features

- *Standards Compliant*: Follows Prometheus naming conventions and exposition formats, enforces base guarantees.
- *Type Safe*: Prevents common configuration errors through Swift's type system.
- *Thread Safe*: Operations use internal locking and conform to `Sendable`.
- *Flexible Metric Labeling*: Supports flexible metric label structures with consistency guarantees.
- *Swift Metrics Compatible*: Use the native Prometheus client API implemented in this library or integrate with [Swift Metrics](doc:swift-metrics).

For general Prometheus guidance, see the [Prometheus Documentation][prometheus-docs].

## Installation

``Prometheus`` is available through Swift Package Manager. To include it in your project add the 
following dependency to your `Package.swift`:

```swift
  .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0")
```

Next, add the dependency to your target:

```swift
  .target(
    name: "MyTarget",
    dependencies: [
      // your other dependencies
      .product(name: "Prometheus", package: "swift-prometheus"),
    ]
  ),
```

## Usage

In your Swift file you must first `import Prometheus`:

```swift
import Prometheus
```

Create a ``PrometheusCollectorRegistry`` instance and register, for instance, a ``Counter``:

```swift
let registry = PrometheusCollectorRegistry()

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

httpRequestsGet.increment(by: 5.0)
```

Emit all registered metrics to the Prometheus text exposition format:

```swift
let output = registry.emitToString()
print(output)
```

```sh
# HELP myapp_http_requests_total Total HTTP requests
# TYPE myapp_http_requests_total counter
myapp_http_requests_total{method="GET",status="200"} 5.0
```

Unregister a ``Counter``:

```swift
registry.unregisterCounter(httpRequestsGet)
```

Explore a detailed usage guide at <doc:labels>.


## Topics

### Getting Started

- <doc:labels>
- <doc:swift-metrics>

### Registry

- ``PrometheusCollectorRegistry``
- ``PrometheusMetricsFactory``

### Metrics

- ``Counter``
- ``Gauge``
- ``Histogram``
- ``DurationHistogram``
- ``ValueHistogram``

### Configuration

- ``MetricNameDescriptor``

[prometheus-docs]: https://prometheus.io/docs/introduction/overview/
