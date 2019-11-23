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

        let gaugeTwo = prom.createGauge(forType: Int.self, named: "my_gauge", helpText: "Gauge for testing", initialValue: 10, withLabelType: BaseLabels.self)
        XCTAssertEqual(gaugeTwo.get(), 20)
        gaugeTwo.inc()
        XCTAssertEqual(gauge.get(), 21)
        XCTAssertEqual(gaugeTwo.get(), 21)
        
        XCTAssertEqual(gauge.collect(), "# HELP my_gauge Gauge for testing\n# TYPE my_gauge gauge\nmy_gauge 21\nmy_gauge{myValue=\"labels\"} 20")
    }
}
