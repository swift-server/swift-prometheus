import XCTest
@testable import Prometheus

var isCITestRun: Bool {
    return ProcessInfo.processInfo.environment.contains { k, v in
        return k == "CI_RUN" && v == "TRUE"
    }
}

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
            XCTAssertEqual(metricsString, "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 30\nmy_counter{myValue=\"labels\"} 30\n")
        }
    }
}
