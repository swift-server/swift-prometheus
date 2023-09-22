# Use Labels in Swift Prometheus

Learn how to use Labels in Prometheus, the benefits of doing so, and how to avoid common mistakes.

## Overview

Prometheus Collectors have a name and they may have labels. Labels specify the metrics further. For
example you might have a ``Counter`` with the name `http_responses_total`. You may now add a label
`code` that specifies the http status response code. This way you are able to query how many http
responses were send. But you can also filter this by response code.

Read more about the benefits of using Labels in the [Prometheus best practices documentation][prometheus-use-labels].

> Note: The naming between Prometheus and Swift-Metrics is a bit confusing. Swift Metrics calls a 
> metric's name its label and they call a metric's labels dimensions. In this article, when we 
> refer to labels, we mean the additional properties that can be added to a metrics name.
>
> | Framework     | Metric name | Additional infos |
> |---------------|-------------|------------------|
> | swift-metrics | `label`     | `dimensions`     |
> | Prometheus    | `name`      | `labels`         |

Please be aware that the ``PrometheusCollectorRegistry`` will create a seperate metric for each 
unique label pair, even though the metric name might be the same. This means that in the example 
below, we will have two independent metrics: 

```swift
let counter200 = registry.makeCounter(name: "http_responses_total", labels: ["code": "200"])
let counter400 = registry.makeCounter(name: "http_responses_total", labels: ["code": "400"])

// handling response code
swift responseCode {
case .ok:
  counter200.increment()
case .badRequest:
  counter400.increment()
default:
  break
}
```

> Important: Please note, that all metrics with the same name, **must** use the same label names. 

Prometheus requires that for the same metric name all labels names must be the same. Swift 
Prometheus ensures that by crashing, if the label names or the metric type does not match a 
previously registered metric with the same name.

#### Examples:

The example below crashes as we try to create a ``Counter`` named `"http_responses_total"` with a 
label `"code"` after a ``Counter`` with the same name without labels was created earlier.

```swift
let counter = registry.makeCounter(name: "http_responses_total")
let counter200 = registry.makeCounter( // 💥 crash
  name: "http_responses_total", 
  labels: ["code": "200"]
)
```

The example below crashes as we try to create a ``Counter`` named `"http_responses_total"` with a 
label `"version"` after a ``Counter`` with the same name but different label name `"code"` was 
created earlier.

```swift
let counter200 = registry.makeCounter(
  name: "http_responses_total",
  labels: ["code": "200"]
)
let counterHTTPVersion1 = registry.makeCounter( // 💥 crash
  name: "http_responses_total", 
  labels: ["version": "1.1"]
)
```

The example below crashes as we try to create a ``Gauge`` named `http_responses_total` with the 
same name as a previously created ``Counter``.

```swift
let counter = registry.makeCounter(name: "http_responses_total")
let gauge = registry.makeGauge(name: "http_responses_total") // 💥 crash
```

[prometheus-use-labels]: https://prometheus.io/docs/practices/instrumentation/#use-labels
