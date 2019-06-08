import XCTest
@testable import Prometheus

final class SwiftPrometheusTests: XCTestCase {
    
    struct BaseLabels: MetricLabels {
        let myValue: String
        
        init() {
            self.myValue = "*"
        }
        
        init(myValue: String) {
            self.myValue = myValue
        }
    }
    
    struct BaseHistogramLabels: HistogramLabels {
        var le: String = ""
        let myValue: String
        
        init() {
            self.myValue = "*"
        }
        
        init(myValue: String) {
            self.myValue = myValue
        }
    }
    
    struct BaseSummaryLabels: SummaryLabels {
        var quantile: String = ""
        let myValue: String
        
        init() {
            self.myValue = "*"
        }
        
        init(myValue: String) {
            self.myValue = myValue
        }
    }
    
    var prom: PrometheusClient!
    
    override func setUp() {
        self.prom = PrometheusClient()
    }
    
    override func tearDown() {
        self.prom = nil
    }
    
    func testCounter() {
        let counter = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10, withLabelType: BaseLabels.self)
        XCTAssertEqual(counter.get(), 10)
        counter.inc(10)
        XCTAssertEqual(counter.get(), 20)
        counter.inc(10, BaseLabels(myValue: "labels"))
        XCTAssertEqual(counter.get(), 20)
        XCTAssertEqual(counter.get(BaseLabels(myValue: "labels")), 20)
        
        XCTAssertEqual(counter.getMetric(), "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 20\nmy_counter{myValue=\"labels\"} 20")
    }
    
    func testGauge() {
        let gauge = prom.createGauge(forType: Int.self, named: "my_gauge", helpText: "Gauge for testing", initialValue: 10, withLabelType: BaseLabels.self)
        XCTAssertEqual(gauge.get(), 10)
        gauge.inc(10)
        XCTAssertEqual(gauge.get(), 20)
        gauge.dec(12)
        XCTAssertEqual(gauge.get(), 8)
        gauge.set(20)
        gauge.inc(10, BaseLabels(myValue: "labels"))
        XCTAssertEqual(gauge.get(), 20)
        XCTAssertEqual(gauge.get(BaseLabels(myValue: "labels")), 20)
        
        XCTAssertEqual(gauge.getMetric(), "# HELP my_gauge Gauge for testing\n# TYPE my_gauge gauge\nmy_gauge 20\nmy_gauge{myValue=\"labels\"} 20")
    }
    
    func testHistogram() {
        let histogram = prom.createHistogram(forType: Double.self, named: "my_histogram", helpText: "Histogram for testing", buckets: [0.5, 1, 2, 3, 5, Double.greatestFiniteMagnitude], labels: BaseHistogramLabels.self)
        histogram.observe(1)
        histogram.observe(2)
        histogram.observe(3)
        
        histogram.observe(3, .init(myValue: "labels"))
        
        XCTAssertEqual(histogram.getMetric(), "# HELP my_histogram Histogram for testing\n# TYPE my_histogram histogram\nmy_histogram_bucket{myValue=\"*\", le=\"0.5\"} 0.0\nmy_histogram_bucket{myValue=\"*\", le=\"1.0\"} 1.0\nmy_histogram_bucket{myValue=\"*\", le=\"2.0\"} 2.0\nmy_histogram_bucket{myValue=\"*\", le=\"3.0\"} 4.0\nmy_histogram_bucket{myValue=\"*\", le=\"5.0\"} 4.0\nmy_histogram_bucket{myValue=\"*\", le=\"+Inf\"} 4.0\nmy_histogram_count{myValue=\"*\"} 4.0\nmy_histogram_sum{myValue=\"*\"} 9.0\nmy_histogram_bucket{myValue=\"labels\", le=\"0.5\"} 0.0\nmy_histogram_bucket{myValue=\"labels\", le=\"1.0\"} 0.0\nmy_histogram_bucket{myValue=\"labels\", le=\"2.0\"} 0.0\nmy_histogram_bucket{myValue=\"labels\", le=\"3.0\"} 1.0\nmy_histogram_bucket{myValue=\"labels\", le=\"5.0\"} 1.0\nmy_histogram_bucket{myValue=\"labels\", le=\"+Inf\"} 1.0\nmy_histogram_count{myValue=\"labels\"} 1.0\nmy_histogram_sum{myValue=\"labels\"} 3.0")
    }
    
    func testSummary() {
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        
        summary.observe(1)
        summary.observe(2)
        summary.observe(4)
        summary.observe(10000)
        
        summary.observe(123, .init(myValue: "labels"))
        
        XCTAssertEqual(summary.getMetric(), "# HELP my_summary Summary for testing\n# TYPE my_summary summary\nmy_summary{quantile=\"0.5\", myValue=\"*\"} 4.0\nmy_summary{quantile=\"0.9\", myValue=\"*\"} 10000.0\nmy_summary{quantile=\"0.99\", myValue=\"*\"} 10000.0\nmy_summary_count{myValue=\"*\"} 5.0\nmy_summary_sum{myValue=\"*\"} 10130.0\nmy_summary{quantile=\"0.5\", myValue=\"labels\"} 123.0\nmy_summary{quantile=\"0.9\", myValue=\"labels\"} 123.0\nmy_summary{quantile=\"0.99\", myValue=\"labels\"} 123.0\nmy_summary_count{myValue=\"labels\"} 1.0\nmy_summary_sum{myValue=\"labels\"} 123.0")
    }
}
