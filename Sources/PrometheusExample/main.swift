import Prometheus

struct MyCodable: MetricLabels {
    var thing: String
    
    init() {
        self.thing = "*"
    }
    
    init(_ thing: String) {
        self.thing = thing
    }
}

let codable1 = MyCodable("Thing1")
let codable2 = MyCodable("Thing2")

//let counter = Counter<Int, MyCodable>("some_test_value", "This value holds just a random imcrementer :)", 0)
//
//counter.inc(5, codable1)
//
//counter.inc(5, codable2)
//
//counter.inc(5)
//
//counter.inc(5, codable1)
//
//print(counter.getMetric())
//
//let gauge = Gauge<Int, MyCodable>("some_test_value", "This value holds a random Gauge :)")
//
//gauge.inc(codable2)
//
//gauge.dec()
//
//gauge.inc(1, codable1)
//
//let arr = [1, 2, 3, 4]
//
//gauge.set(arr.count)
//
//print(gauge.getMetric())
//
//struct HistogramCodable: HistogramLabels {
//    var le: String = ""
//}
//
//let histogram = Histogram<Int, HistogramCodable>("my_histogram", "Just a histogram")
//
//histogram.observe(6)
//histogram.observe(6)
//histogram.observe(1)
//histogram.observe(4)
//
//print(histogram.getMetric())

//struct SummaryCodable: SummaryLabels {
//    var quantile: String = ""
//}
//
//let summary = Summary<Int, SummaryCodable>("my_summary", "Just a summary")
//
//summary.observe(4)
//summary.observe(3)
//summary.observe(1)
//summary.observe(3)
//summary.observe(9)
//summary.observe(5)
//
//print(summary.getMetric())
