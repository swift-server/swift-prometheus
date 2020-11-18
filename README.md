[![CircleCI](https://circleci.com/gh/MrLotU/SwiftPrometheus.svg?style=svg)](https://circleci.com/gh/MrLotU/SwiftPrometheus)[![Swift 5.0](https://img.shields.io/badge/swift-5.0-orange.svg?style=flat)](http://swift.org)

# SwiftPrometheus, Prometheus client for Swift

A prometheus client for Swift supporting counters, gauges, histograms, summaries and info.

# Installation

SwiftPrometheus is available through SPM. To include it in your project add the following dependency to your `Package.swift`:
```swift
        .package(url: "https://github.com/MrLotU/SwiftPrometheus.git", from: "1.0.0-alpha")
```

_NOTE: For NIO 1 use `from: "0.4.0-alpha"` instead._

# Usage

To see a working demo, see [PrometheusExample](./Sources/PrometheusExample/main.swift).

First, we have to create an instance of our `PrometheusClient`:

```swift
import Prometheus
let myProm = PrometheusClient()
```

## Usage with SwiftMetrics
_For more details about swift-metrics, please view [the GitHub repo](https://github.com/apple/swift-metrics)._

To use SwiftPrometheus with swift-metrics, you need to configure the backend inside the `MetricsSystem`:

```swift
import Metrics
import Prometheus
let myProm = PrometheusClient()
MetricsSystem.bootstrap(myProm)
```

To use prometheus-specific features in a later stage of your program, or to get your metrics out of the system, there is a convenience method added to `MetricsSystem`:

```swift
// This returns the same instance passed in to `.bootstrap()` earlier.
let promInstance = try MetricsSystem.prometheus()
print(promInstance.collect())
```

You can then use the same APIs described in the rest of this README.

## Counter

Counters go up (they can only increase in value), and reset when the process restarts.

```swift
let counter = myProm.createCounter(forType: Int.self, named: "my_counter")
counter.inc() // Increment by 1
counter.inc(12) // Increment by given value
```

## Gauge

Gauges can go up and down, they represent a "point-in-time" snapshot of a value. This is similar to the speedometer of a car.

```swift
let gauge = myProm.createGauge(forType: Int.self, named: "my_gauge")
gauge.inc() // Increment by 1
gauge.dec(19) // Decrement by given value
gauge.set(12) // Set to a given value
```

## Histogram

Histograms track the size and number of events in buckets. This allows for aggregatable calculation of quantiles.

```swift
let histogram = myProm.createHistogram(forType: Double.self, named: "my_histogram")
histogram.observe(4.7) // Observe the given value
```

## Summary

Summaries track the size and number of events

```swift
let summary = myProm.createSummary(forType: Double.self, named: "my_summary")
summary.observe(4.7) // Observe the given value
```

## Labels
All metric types support adding labels, allowing for grouping of related metrics.

Example with a counter:

```swift
struct RouteLabels: MetricLabels {
   var route: String = "*"
}

let counter = myProm.createCounter(forType: Int.self, named: "my_counter", helpText: "Just a counter", withLabelType: RouteLabels.self)

let counter = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Just a counter", withLabelType: RouteLabels.self)

counter.inc(12, .init(route: "/"))
```

# Exporting

Prometheus itself is designed to "pull" metrics from a destination. Following this pattern, SwiftPrometheus is designed to expose metrics, as opposed to submitted/exporting them directly to Prometheus itself. SwiftPrometheus produces a formatted string that Prometheus can parse, which can be integrated into your own application.

By default, this should be accessible on your main serving port, at the `/metrics` endpoint. An example in [Vapor](https://vapor.codes)  4 syntax looks like:

```swift
app.get("metrics") { req -> EventLoopFuture<String> in
    let promise = req.eventLoop.makePromise(of: String.self)
    DispatchQueue.global().async {
        do {
            try MetricsSystem.prometheus().collect(into: promise)
        } catch {
            promise.fail(error)
        }
    }
    return promise.futureResult
}
```

# Contributing

All contributions are most welcome!

If you think of some cool new feature that should be included, please [create an issue](https://github.com/MrLotU/SwiftPrometheus/issues/new/choose). Or, if you want to implement it yourself, [fork this repo](https://github.com/MrLotU/SwiftPrometheus/fork) and submit a PR!

If you find a bug or have issues, please [create an issue](https://github.com/MrLotU/SwiftPrometheus/issues/new/choose) explaining your problems. Please include as much information as possible, so it's easier for me to reproduce (Framework, OS, Swift version, terminal output, etc.)
