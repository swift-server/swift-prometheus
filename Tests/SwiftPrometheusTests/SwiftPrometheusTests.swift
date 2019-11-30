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
        
        XCTAssertEqual(counter.collect(), "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 20\nmy_counter{myValue=\"labels\"} 20")
    }

    func testMultipleCounter() {
        let counter = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10, withLabelType: BaseLabels.self)
        counter.inc(10)
        XCTAssertEqual(counter.get(), 20)

        let counterTwo = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10, withLabelType: BaseLabels.self)
        counter.inc(10)
        XCTAssertEqual(counterTwo.get(), 30)
        counterTwo.inc(20, BaseLabels(myValue: "labels"))

        XCTAssertEqual(counter.collect(), "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 30\nmy_counter{myValue=\"labels\"} 30")
        self.prom.collect { metricsString in
            XCTAssertEqual(metricsString, "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 30\nmy_counter{myValue=\"labels\"} 30")
        }
    }
    
    func testSummary() {
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        let summaryTwo = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        
        summary.observe(1)
        summary.observe(2)
        summary.observe(4)
        summaryTwo.observe(10000)
        
        summary.observe(123, .init(myValue: "labels"))
        
        XCTAssertEqual(summary.collect(), "# HELP my_summary Summary for testing\n# TYPE my_summary summary\nmy_summary{quantile=\"0.5\", myValue=\"*\"} 4.0\nmy_summary{quantile=\"0.9\", myValue=\"*\"} 10000.0\nmy_summary{quantile=\"0.99\", myValue=\"*\"} 10000.0\nmy_summary_count{myValue=\"*\"} 5.0\nmy_summary_sum{myValue=\"*\"} 10130.0\nmy_summary{quantile=\"0.5\", myValue=\"labels\"} 123.0\nmy_summary{quantile=\"0.9\", myValue=\"labels\"} 123.0\nmy_summary{quantile=\"0.99\", myValue=\"labels\"} 123.0\nmy_summary_count{myValue=\"labels\"} 1.0\nmy_summary_sum{myValue=\"labels\"} 123.0")
    }
}
