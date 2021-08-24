import XCTest
import NIO
@testable import Prometheus
@testable import CoreMetrics

final class GaugeTests: XCTestCase {
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
    var group: EventLoopGroup!
    var eventLoop: EventLoop {
        return group.next()
    }
    
    override func setUp() {
        self.prom = PrometheusClient()
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        MetricsSystem.bootstrapInternal(PrometheusMetricsFactory(client: prom))
    }
    
    override func tearDown() {
        self.prom = nil
        try! self.group.syncShutdownGracefully()
    }
    
    func testGaugeSwiftMetrics() {
        let gauge = Gauge(label: "my_gauge")
        
        gauge.record(10)
        gauge.record(12)
        gauge.record(20)
        
        let gaugeTwo = Gauge(label: "my_gauge", dimensions: [("myValue", "labels")])
        gaugeTwo.record(10)

        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        
        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE my_gauge gauge
        my_gauge 20.0
        my_gauge{myValue=\"labels\"} 10.0\n
        """)
    }

    #if os(Linux)
    func testGaugeTime() {
        let gauge = prom.createGauge(forType: Double.self, named: "my_gauge")
        let delay = 0.05
        gauge.time {
            Thread.sleep(forTimeInterval: delay)
        }
        // Using starts(with:) here since the exact subseconds might differ per-test.
        XCTAssert(gauge.collect().starts(with: """
        # TYPE my_gauge gauge
        my_gauge 0.05
        """))
    }
    #endif
    
    func testGaugeStandalone() {
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
        
        XCTAssertEqual(gauge.collect(), """
        # HELP my_gauge Gauge for testing
        # TYPE my_gauge gauge
        my_gauge 21
        my_gauge{myValue="labels"} 20
        """)
    }
}
