// swift-tools-version:5.7
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2018-2023 SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Benchmark
import Prometheus

let benchmarks = {
    Benchmark.defaultConfiguration.maxDuration = .seconds(5)
    Benchmark.defaultConfiguration.scalingFactor = .kilo

    let registry = PrometheusCollectorRegistry()

    func metricsDimensions(_ idx: Int) -> [(String, String)] {
        [
            ("job", "api_server_\(idx)"),
            ("handler", "/api/handler_\(idx)"),
            ("status_code", "200"),
            ("version", "\(idx).0.0"),
        ]
    }

    Benchmark("1 - Metrics: Counter benchmark") { benchmark in
        let ctr = registry.makeCounter(name: "counter_1", labels: metricsDimensions(1))
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(ctr.increment())
        }
    }

    Benchmark("2 - Metrics: Gauge benchmark") { benchmark in
        let gauge = registry.makeGauge(name: "gauge_1", labels: metricsDimensions(2))
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(gauge.increment())
        }
    }

    Benchmark("3 - Metrics: Histogram benchmark") { benchmark in
        let histogram = registry.makeDurationHistogram(name: "histogram_1", labels: metricsDimensions(3),
                                                       buckets: [
                                                           .milliseconds(100),
                                                           .milliseconds(250),
                                                           .milliseconds(500),
                                                           .seconds(1),
                                                       ])
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            histogram.record(Duration.milliseconds(400))
        }
    }

    Benchmark("4 - Metrics: export 5000 metrics", 
              configuration: .init(scalingFactor: .one)) { benchmark in
        let metricsCount = 5000

        let registryExport = PrometheusCollectorRegistry()

        var counterArray = [Counter]()
        var gaugeArray = [Gauge]()
        var buffer = [UInt8]()

        let counterExportSize = 620_000
        counterArray.reserveCapacity(metricsCount)
        gaugeArray.reserveCapacity(metricsCount)
        buffer.reserveCapacity(counterExportSize)

        for i in 0..<(metricsCount / 2) {
            let counter = registryExport.makeCounter(name: "http_requests_total", labels: metricsDimensions(i))
            counter.increment()
            counterArray.append(counter)

            let gauge = registryExport.makeGauge(name: "export_gauge_\(i)", labels: metricsDimensions(i))
            gauge.increment()
            gaugeArray.append(gauge)
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(registryExport.emit(into: &buffer))

        }
        benchmark.stopMeasurement()
        buffer.removeAll(keepingCapacity: true)
    }
}
