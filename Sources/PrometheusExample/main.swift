import Prometheus

struct MyCodable: MetricLabels {
    var thing: String = "*"
}

let codable1 = MyCodable(thing: "Thing1")
let codable2 = MyCodable(thing: "Thing2")

let counter = Prometheus.shared.createCounter(forType: Int.self, named: "my_counter", helpText: "Just a counter", initialValue: 12)

counter.inc(5)

let gauge = Prometheus.shared.createGauge(forType: Int.self, named: "my_gauge", helpText: "Just a gauge", initialValue: 0)

gauge.set(123)

let histogram = Prometheus.shared.createHistogram(forType: Double.self, named: "my_histogram", helpText: "Just a histogram")

for _ in 0...Int.random(in: 10...50) {
    histogram.observe(Double.random(in: 0...1))
}

struct SummaryThing: SummaryLabels {
    var quantile: String = ""
    let route: String

    init() {
        self.route = "*"
    }
    
    init(_ route: String) {
        self.route = route
    }
}

let summary = Prometheus.shared.createSummary(forType: Double.self, named: "my_summary", helpText: "Just a summary", labels: SummaryThing())

for _ in 0...Int.random(in: 100...1000) {
    summary.observe(Double.random(in: 0...10000))
}

for _ in 0...Int.random(in: 100...1000) {
    summary.observe(Double.random(in: 0...10000), SummaryThing("/test"))
}

print(Prometheus.shared.getMetrics())
