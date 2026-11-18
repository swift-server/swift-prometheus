# Swift Metrics as Backend

Learn how to use Swift Metrics as a backend for Swift Prometheus.

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

### Modifying the Prometheus Export

Now that we have setup the Prometheus export, lets discuss which configuration options there are to
modify the Swift Metrics export.

#### Using a specific Collector Registry as the Export Target

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

#### Modifying Swift metrics names and labels

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

#### Defining Buckets for Histograms

Default buckets:

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

Buckets by name:

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

Buckets from configuration:

Configuration is opt-in. The existing `PrometheusMetricsFactory(registry:)` initializer always
uses built-in defaults. To let operators tune buckets through environment variables, pass an
environment-backed reader to ``PrometheusMetricsFactory/Configuration``:

```swift
import Configuration

let config = ConfigReader(provider: EnvironmentVariablesProvider())
let configuration = try await PrometheusMetricsFactory.Configuration(config: config)
let factory = PrometheusMetricsFactory(configuration: configuration)
MetricsSystem.bootstrap(factory)
```

The configuration reader initializer requires macOS 15, iOS 18, watchOS 11, tvOS 18, or visionOS 2
on Apple platforms. The existing initializer retains its original platform support.
The reader is accessed once when the configuration is created; values do not reload automatically.
Loading configuration is asynchronous so that missing keys can use defaults while provider and type errors are thrown.
Creating the factory from the loaded configuration is synchronous.

Operators can then set:

```bash
export SWIFT_PROMETHEUS_DEFAULT_HISTOGRAM_BUCKETS=0.05,0.1,0.25,0.5,1,5
```

Values from `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAM_BUCKETS` are interpreted as seconds for duration
histograms and as raw upper bounds for value histograms. Bucket upper bounds must be finite,
strictly increasing numbers, and duration bucket upper bounds must additionally be zero or greater.
If the variable is unset, the built-in default buckets are used unless a more specific value is set.
Buckets that are configured explicitly in code, as shown in the examples above, take precedence
over the environment.

If duration and value histograms need different default buckets, use the more specific
environment variables:

```bash
export SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS=0.05,0.1,0.25,0.5,1,5
export SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS=5,25,100,500,1000
```

These specific variables take precedence over `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAM_BUCKETS`.
The configuration initializer throws if it cannot read a supplied value as a string array
or if an array contains invalid bounds. Only missing values fall back to shared or built-in defaults.
Shared bounds must meet the duration requirements when used for duration histograms.

Applications can supply any Swift Configuration provider. The following keys expect **arrays of strings**.
The environment provider splits comma-separated values; JSON and in-memory providers use native string arrays:

| Configuration key | Environment variable |
| --- | --- |
| `swift.prometheus.default.histogram.buckets` | `SWIFT_PROMETHEUS_DEFAULT_HISTOGRAM_BUCKETS` |
| `swift.prometheus.default.duration.histogram.buckets` | `SWIFT_PROMETHEUS_DEFAULT_DURATION_HISTOGRAM_BUCKETS` |
| `swift.prometheus.default.value.histogram.buckets` | `SWIFT_PROMETHEUS_DEFAULT_VALUE_HISTOGRAM_BUCKETS` |

For example, an in-memory provider can supply the shared buckets with:

```swift
let config = ConfigReader(
    provider: InMemoryProvider(values: [
        "swift.prometheus.default.histogram.buckets": .init(
            .stringArray(["0.05", "0.1", "0.5", "1"]),
            isSecret: false
        )
    ])
)
let configuration = try await PrometheusMetricsFactory.Configuration(config: config)
let factory = PrometheusMetricsFactory(configuration: configuration)
```

The public configuration type can also be configured directly, without a reader:

```swift
var configuration = PrometheusMetricsFactory.Configuration()
configuration.defaultDurationHistogramBuckets = [.milliseconds(100), .seconds(1)]
configuration.defaultValueHistogramBuckets = [10, 100, 1000]
let factory = PrometheusMetricsFactory(configuration: configuration)
```

Duration bounds must also be representable as `Duration`. Assign factory bucket properties before
creating metrics to override the configuration, or use the per-label dictionaries shown above.

[Swift Metrics]: https://github.com/apple/swift-metrics
