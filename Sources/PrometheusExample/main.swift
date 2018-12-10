import Prometheus

struct MyCodable: MetricLabels {
   var thing: String = "*"
}

let codable1 = MyCodable(thing: "Thing1")
let codable2 = MyCodable(thing: "Thing2")

let counter = Prometheus.shared.createCounter(forType: Int.self, named: "my_counter", helpText: "Just a counter", initialValue: 12, withLabelType: MyCodable.self)

counter.inc(5)
counter.inc(Int.random(in: 0...100), codable2)
counter.inc(Int.random(in: 0...100), codable1)

let gauge = Prometheus.shared.createGauge(forType: Int.self, named: "my_gauge", helpText: "Just a gauge", initialValue: 12, withLabelType: MyCodable.self)

gauge.inc(100)
gauge.inc(Int.random(in: 0...100), codable2)
gauge.inc(Int.random(in: 0...100), codable1)

struct HistogramThing: HistogramLabels {
   var le: String = ""
   let route: String

   init() {
       self.route = "*"
   }

   init(_ route: String) {
       self.route = route
   }
}

let histogram = Prometheus.shared.createHistogram(forType: Double.self, named: "my_histogram", helpText: "Just a histogram", labels: HistogramThing.self)

for _ in 0...Int.random(in: 10...50) {
   histogram.observe(Double.random(in: 0...1))
}

for _ in 0...Int.random(in: 10...50) {
   histogram.observe(Double.random(in: 0...1), HistogramThing("/test"))
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

let summary = Prometheus.shared.createSummary(forType: Double.self, named: "my_summary", helpText: "Just a summary", labels: SummaryThing.self)

for _ in 0...Int.random(in: 100...1000) {
   summary.observe(Double.random(in: 0...10000))
}

for _ in 0...Int.random(in: 100...1000) {
   summary.observe(Double.random(in: 0...10000), SummaryThing("/test"))
}

struct MyInfoStruct: MetricLabels {
   let version: String
   let major: String
   
   init() {
       self.version = "1.0.0"
       self.major = "1"
   }
   
   init(_ v: String, _ m: String) {
       self.version = v
       self.major = m
   }
}

let info = Prometheus.shared.createInfo(named: "my_info", helpText: "Just some info", labelType: MyInfoStruct.self)

info.info(MyInfoStruct("2.0.0", "2"))

print(Prometheus.shared.getMetrics())
