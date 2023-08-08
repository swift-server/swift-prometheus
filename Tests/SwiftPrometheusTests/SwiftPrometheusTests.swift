import XCTest
@testable import Prometheus

var isCITestRun: Bool {
    return ProcessInfo.processInfo.environment.contains { k, v in
        return k == "CI_RUN" && v == "TRUE"
    }
}

final class SwiftPrometheusTests: XCTestCase {

    let baseLabels = DimensionLabels([("myValue", "labels")])
    
    var prom: PrometheusClient!
    
    override func setUp() {
        self.prom = PrometheusClient()
    }
    
    override func tearDown() {
        self.prom = nil
    }
    
    func testCounter() {
        let counter = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10)
        XCTAssertEqual(counter.get(), 10)
        counter.inc(10)
        XCTAssertEqual(counter.get(), 20)
        counter.inc(10, baseLabels)
        XCTAssertEqual(counter.get(), 20)
        XCTAssertEqual(counter.get(baseLabels), 20)
        
        XCTAssertEqual(counter.collect(), "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 20\nmy_counter{myValue=\"labels\"} 20")
    }

    func testMultipleCounter() {
        let counter = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10)
        counter.inc(10)
        XCTAssertEqual(counter.get(), 20)

        let counterTwo = prom.createCounter(forType: Int.self, named: "my_counter", helpText: "Counter for testing", initialValue: 10)
        counter.inc(10)
        XCTAssertEqual(counterTwo.get(), 30)
        counterTwo.inc(20, baseLabels)

        XCTAssertEqual(counter.collect(), "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 30\nmy_counter{myValue=\"labels\"} 30")
        self.prom.collect { metricsString in
            XCTAssertEqual(metricsString, "# HELP my_counter Counter for testing\n# TYPE my_counter counter\nmy_counter 30\nmy_counter{myValue=\"labels\"} 30\n")
        }
    }

    func testCounterDoesNotReportWithNoLabelUsed() {
        let counter = prom.createCounter(forType: Int.self, named: "my_counter")
        counter.inc(1, [("a", "b")])

        XCTAssertEqual(counter.collect(), """
        # TYPE my_counter counter
        my_counter{a="b"} 1
        """)

        counter.inc()

        XCTAssertEqual(counter.collect(), """
        # TYPE my_counter counter
        my_counter 1
        my_counter{a="b"} 1
        """)
    }

}
