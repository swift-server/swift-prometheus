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

print(Prometheus.shared.getMetrics())
