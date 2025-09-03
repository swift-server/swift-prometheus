# Swift Prometheus

[![sswg:sandbox](https://img.shields.io/badge/sswg-sandbox-yellow.svg)][SSWG-Incubation]
[![Documentation](http://img.shields.io/badge/read_the-docs-2196f3.svg)][Documentation]

A Swift client library for [Prometheus Monitoring System](https://github.com/prometheus/prometheus).

`swift-prometheus` supports creating `Counter`s, `Gauge`s and `Histogram`s, updating metric values, and exposing their values in the Prometheus text format.

## Installation and Usage

Please refer to the [Documentation][Documentation] for installation, usage instructions, and implementation details including Prometheus standards compliance.

For general Prometheus guidance, see [Prometheus Monitoring System][prometheus-docs].

## Security

Please see [SECURITY.md](SECURITY.md) for details on the security process.

## Contributing

We welcome all contributions to `swift-prometheus`! For feature requests or bug reports, please [create an issue](https://github.com/swift-server/swift-prometheus/issues/new) with detailed information including Swift version, platform, and reproduction steps. To contribute code, [fork this repo](https://github.com/swift-server/swift-prometheus/fork) and submit a pull request with tests and documentation updates.

## Benchmarks

Benchmarks are located in the [Benchmarks](/Benchmarks/) subfolder and use the [`package-benchmark`](https://github.com/ordo-one/package-benchmark) plugin. See the [Benchmarks Getting Started]((https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/gettingstarted#Installing-Prerequisites-and-Platform-Support)) guide for installation instructions. Run benchmarks by navigating to Benchmarks and executing:

```
swift package benchmark
```

For more information please refer to `swift package benchmark --help` or the [`package-benchmark` Documentation](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark).


[Documentation]: https://swiftpackageindex.com/swift-server/swift-prometheus/documentation/prometheus
[prometheus-docs]: https://prometheus.io/docs/introduction/overview/
[SSWG-Incubation]: https://www.swift.org/sswg/incubation-process.html
