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
        let semaphore = DispatchSemaphore(value: 0)
        
        let counter = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10, withLabelType: BaseLabels.self)
        XCTAssertEqual(counter.get(), 10)
        counter.inc(10) { int in
            XCTAssertEqual(counter.get(), 20)
            XCTAssertEqual(int, 20)
        }
        counter.inc(10, BaseLabels(myValue: "labels")) { int in
            XCTAssertEqual(counter.get(), 20)
            semaphore.signal()
        }
        semaphore.wait()
        XCTAssertEqual(counter.get(BaseLabels(myValue: "labels")), 20)
        
        counter.getMetric { metric in
            XCTAssertEqual(metric, "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 20\nmy_counter{myValue=\"labels\"} 20")
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    func testGauge() {
        let semaphore = DispatchSemaphore(value: 0)
        
        let gauge = prom.createGauge(forType: Int.self, named: "my_gauge", helpText: "Gauge for testing", initialValue: 10, withLabelType: BaseLabels.self)
        XCTAssertEqual(gauge.get(), 10)
        gauge.inc(10) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        XCTAssertEqual(gauge.get(), 20)
        gauge.dec(12) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        XCTAssertEqual(gauge.get(), 8)
        gauge.set(20) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        gauge.inc(10, BaseLabels(myValue: "labels")) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        XCTAssertEqual(gauge.get(), 20)
        XCTAssertEqual(gauge.get(BaseLabels(myValue: "labels")), 20)
        
        gauge.getMetric { metric in
            XCTAssertEqual(metric, "# HELP my_gauge Gauge for testing\n# TYPE my_gauge gauge\nmy_gauge 20\nmy_gauge{myValue=\"labels\"} 20")
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    func testHistogram() {
        let semaphore = DispatchSemaphore(value: 0)

        let histogram = prom.createHistogram(forType: Double.self, named: "my_histogram", helpText: "Histogram for testing", buckets: [0.5, 1, 2, 3, 5, Double.greatestFiniteMagnitude], labels: BaseHistogramLabels.self)
        histogram.observe(1) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        histogram.observe(2) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        histogram.observe(3) { _ in
            semaphore.signal()
        }
        semaphore.wait()
        
        histogram.observe(3, .init(myValue: "labels")) { _ in
            semaphore.signal()
        }
        semaphore.wait()
        var metricOutput = ""
        histogram.getMetric { metric in
            metricOutput = metric
            semaphore.signal()
        }
        semaphore.wait()

        XCTAssertEqual(metricOutput, "# HELP my_histogram Histogram for testing\n# TYPE my_histogram histogram\nmy_histogram_bucket{myValue=\"*\", le=\"0.5\"} 0.0\nmy_histogram_bucket{myValue=\"*\", le=\"1.0\"} 1.0\nmy_histogram_bucket{myValue=\"*\", le=\"2.0\"} 2.0\nmy_histogram_bucket{myValue=\"*\", le=\"3.0\"} 4.0\nmy_histogram_bucket{myValue=\"*\", le=\"5.0\"} 4.0\nmy_histogram_bucket{myValue=\"*\", le=\"+Inf\"} 4.0\nmy_histogram_count{myValue=\"*\"} 4.0\nmy_histogram_sum{myValue=\"*\"} 9.0\nmy_histogram_bucket{myValue=\"labels\", le=\"0.5\"} 0.0\nmy_histogram_bucket{myValue=\"labels\", le=\"1.0\"} 0.0\nmy_histogram_bucket{myValue=\"labels\", le=\"2.0\"} 0.0\nmy_histogram_bucket{myValue=\"labels\", le=\"3.0\"} 1.0\nmy_histogram_bucket{myValue=\"labels\", le=\"5.0\"} 1.0\nmy_histogram_bucket{myValue=\"labels\", le=\"+Inf\"} 1.0\nmy_histogram_count{myValue=\"labels\"} 1.0\nmy_histogram_sum{myValue=\"labels\"} 3.0")
    }
    
    func testInfo() {
        let info = prom.createInfo(named: "my_info", helpText: "Info for testing", labelType: BaseLabels.self)
        info.info(.init(myValue: "testing"))
        
        let semaphore = DispatchSemaphore(value: 0)
        info.getMetric { metric in
            XCTAssertEqual(metric, "# HELP my_info Info for testing\n# TYPE my_info info\nmy_info{myValue=\"testing\"} 1.0")
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    func testSummary() {
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        let semaphore = DispatchSemaphore(value: 0)
        
        summary.observe(1) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        summary.observe(2) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        summary.observe(4) { _ in
            semaphore.signal()
        }
        semaphore.wait()

        summary.observe(10000) { _ in
            semaphore.signal()
        }
        semaphore.wait()
        
        summary.observe(123, .init(myValue: "labels")) { _ in
            semaphore.signal()
        }
        semaphore.wait()
        
        var outputMetric = ""
        summary.getMetric { metric in
            outputMetric = metric
            semaphore.signal()
        }
        semaphore.wait()

        XCTAssertEqual(outputMetric, "# HELP my_summary Summary for testing\n# TYPE my_summary summary\nmy_summary{quantile=\"0.5\", myValue=\"*\"} 4.0\nmy_summary{quantile=\"0.9\", myValue=\"*\"} 10000.0\nmy_summary{quantile=\"0.99\", myValue=\"*\"} 10000.0\nmy_summary_count{myValue=\"*\"} 5.0\nmy_summary_sum{myValue=\"*\"} 10130.0\nmy_summary{quantile=\"0.5\", myValue=\"labels\"} 123.0\nmy_summary{quantile=\"0.9\", myValue=\"labels\"} 123.0\nmy_summary{quantile=\"0.99\", myValue=\"labels\"} 123.0\nmy_summary_count{myValue=\"labels\"} 1.0\nmy_summary_sum{myValue=\"labels\"} 123.0")
    }
    
    static var allTests = [
        ("testCounter", testCounter),
        ("testGauge", testGauge),
        ("testHistogram", testHistogram),
        ("testInfo", testInfo),
        ("testSummary", testSummary)
    ]
}
