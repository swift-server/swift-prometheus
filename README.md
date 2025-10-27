# Swift Prometheus

[![sswg:sandbox](https://img.shields.io/badge/sswg-sandbox-yellow.svg)][SSWG-Incubation]
[![Documentation](http://img.shields.io/badge/read_the-docs-2196f3.svg)][Documentation]  
[![Supported Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fswift-server%2Fswift-prometheus%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/swift-server/swift-prometheus)
[![Supported Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fswift-server%2Fswift-prometheus%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/swift-server/swift-prometheus)

A Swift client library for [Prometheus Monitoring System](https://github.com/prometheus/prometheus).

This can also be used a backend implementation for [Swift Metrics](https://github.com/apple/swift-metrics).

`swift-prometheus` supports creating `Counter`s, `Gauge`s and `Histogram`s, updating metric values, and exposing their values in the Prometheus text format.

## Installation and Usage

Please see the `swift-prometheus` [DocC Documentation][Documentation] for details on installation, usage, implementation, and Prometheus standards compliance.

For general Prometheus guidance, see [Prometheus Monitoring System][prometheus-docs].

## Security

Please see [SECURITY.md](SECURITY.md) for details on the security process.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) to learn how you can help, or browse our [open issues](https://github.com/swift-server/swift-prometheus/issues) to find a place to start.

## Benchmarks

Benchmarks are located in the [Benchmarks](/Benchmarks/) subfolder and use the [`package-benchmark`](https://github.com/ordo-one/package-benchmark) plugin. See the [Benchmarks Getting Started](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/gettingstarted#Installing-Prerequisites-and-Platform-Support) guide for installation instructions. Run benchmarks by navigating to Benchmarks and executing:

```
swift package benchmark
```

For more information please refer to `swift package benchmark --help` or the [`package-benchmark` Documentation](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark).

[Documentation]: https://swiftpackageindex.com/swift-server/swift-prometheus/documentation/prometheus
[prometheus-docs]: https://prometheus.io/docs/introduction/overview/
[SSWG-Incubation]: https://www.swift.org/sswg/incubation-process.html
