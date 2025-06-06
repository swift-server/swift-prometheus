# Emit metrics collected by Swift Metrics

Learn how Swift Prometheus integrates with Swift Metrics – an abstract API that is widely used in 
the swift-server ecosystem.

## Overview

Swift ``Prometheus`` integrates with Swift Metrics v2. Swift Metrics provides an interface to allow 
library authors and application developers to emit metrics without specifying a concrete metric 
backend. 

### Adding the dependency

First you need to add the `swift-metrics` and `swit-prometheus` dependency to your Package.swift 
in the `dependencies` section:

```swift
  dependencies: [
    // your other dependencies
    .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.1"),
  ]
```

Next, add the dependencies to your target.

```swift
  .target(
    name: "MyTarget",
    dependencies: [
      .product(name: "Prometheus", package: "swift-prometheus"),
      .product(name: "Metrics", package: "swift-metrics"),
    ]
  ),
```

### Setting up Prometheus to export to Swift Metrics

At application startup you need to create a ``PrometheusMetricsFactory`` and register it as
the metrics backend for swift-metrics:

```swift
import Metrics
import Prometheus

func main() {
  let factory = PrometheusMetricsFactory()
  MetricsSystem.bootstrap(factory)

  // the rest of your application code
}
```

## Modifying the Prometheus Export

Now that we have setup the Prometheus export, lets discuss which configuration options there are to
modify the Swift Metrics export.

### Using a specific Collector Registry as the Export Target

If you create a `PrometheusMetricsFactory()` without specifying a ``PrometheusCollectorRegistry``,
it will use ``PrometheusMetricsFactory/defaultRegistry`` as the underlying collector registry.
To use a different collector registry pass your ``PrometheusCollectorRegistry`` when creating 
``PrometheusMetricsFactory/init(registry:)``:

```swift
let registry = PrometheusCollectorRegistry()
let factory = PrometheusMetricsFactory(registry: registry)
MetricsSystem.bootstrap(factory)
```

You can also overwrite the ``PrometheusMetricsFactory/registry`` by setting it explicitly:

```swift
let registry = PrometheusCollectorRegistry()
var factory = PrometheusMetricsFactory()
factory.registry = registry
MetricsSystem.bootstrap(factory)
```

### Modifying Swift metrics names and labels

When you create a ``PrometheusMetricsFactory``, you can also set the 
``PrometheusMetricsFactory/nameAndLabelSanitizer`` to modify the metric names and labels:

```swift
var factory = PrometheusMetricsFactory()
factory.nameAndLabelSanitizer = { (name, labels)
  switch name {
  case "my_counter":
    return ("counter", labels)
  default:
    return (name, labels)
  }
}
MetricsSystem.bootstrap(factory)

// somewhere else
Metrics.Counter(label: "my_counter") // will show up in Prometheus exports as `counter`
```

This can be particularly usefull, if you want to change the names and labels for metrics that are
generated in a third party library.

> Important: Please note, that all Prometheus metrics with the same name, **must** use the same 
> label names.
> Use the ``PrometheusMetricsFactory/nameAndLabelSanitizer`` to ensure this remains true metrics 
> that are created in third party libraries. See <doc:labels> for more information about this.

### Defining Buckets for Histograms

#### Default buckets

Swift Metric `Timer`s are backed by a Prometheus ``DurationHistogram`` and Swift Metric 
`Recorder`s that aggregate are backed by a Prometheus ``ValueHistogram``. As a user, you can 
specify which buckets shall be used within the backing ``Histogram``s.

```swift
var factory = PrometheusMetricsFactory()

factory.defaultDurationHistogramBuckets = [
  .milliseconds(5),
  .milliseconds(10),
  .milliseconds(25),
  .milliseconds(50),
  .milliseconds(100),
]

factory.defaultValueHistogramBuckets = [
  5,
  10,
  25,
  50,
  100,
  250,
]
MetricsSystem.bootstrap(factory)

// somewhere else
Timer(label: "my_timer") // will use the buckets specified in `defaultDurationHistogramBuckets`
Recorder(label: "my_recorder", aggregate: true) // will use the buckets specified in `defaultValueHistogramBuckets`
```

#### Buckets by name

You can also specify the buckets by metric name:

```swift
var factory = PrometheusMetricsFactory()

factory.defaultDurationHistogramBuckets = [
  .milliseconds(5),
  .milliseconds(10),
  .milliseconds(25),
  .milliseconds(50),
  .milliseconds(100),
]

factory.durationHistogramBuckets["long"] = [
  .seconds(5),
  .seconds(10),
  .seconds(25),
  .seconds(50),
  .seconds(100),
] 
```

Now a `Timer` with the label "long" will use the buckets  
`[.seconds(5), .seconds(10), .seconds(25), .seconds(50), .seconds(100),]`, whereas any other 
`Timer` will use the default buckets 
`[.milliseconds(5), .milliseconds(10), .milliseconds(25), .milliseconds(50), .milliseconds(100),]`.

The same functionality is also available for ``ValueHistogram`` and aggregating `Recorder`s.

[Swift Metrics]: https://github.com/apple/swift-metrics
