import XCTest
import NIO
@testable import Prometheus
@testable import CoreMetrics

final class PrometheusMetricsTests: XCTestCase {
    
    var prom: PrometheusClient!
    var group: EventLoopGroup!
    var eventLoop: EventLoop {
        return group.next()
    }
    
    override func setUp() {
        self.prom = PrometheusClient()
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        MetricsSystem.bootstrapInternal(prom)
    }
    
    override func tearDown() {
        self.prom = nil
        try! self.group.syncShutdownGracefully()
    }
    
    func testCounter() {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterTwo = Counter(label: "my_counter", dimensions: [("myValue", "labels")])
        counterTwo.increment(by: 10)
        
        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        
        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE my_counter counter
        my_counter 10
        my_counter{myValue=\"labels\"} 10
        """)
    }

    func testGauge() {
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
        my_gauge{myValue=\"labels\"} 10.0
        """)
    }

    func testSummary() {
        let summary = Timer(label: "my_summary")
        
        summary.recordNanoseconds(1)
        summary.recordNanoseconds(2)
        summary.recordNanoseconds(4)
        summary.recordNanoseconds(10000)
        
        let summaryTwo = Timer(label: "my_summary", dimensions: [("myValue", "labels")])
        summaryTwo.recordNanoseconds(123)
        
        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        
        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE my_summary summary
        my_summary{quantile="0.01"} 1.0
        my_summary{quantile="0.05"} 1.0
        my_summary{quantile="0.5"} 4.0
        my_summary{quantile="0.9"} 10000.0
        my_summary{quantile="0.95"} 10000.0
        my_summary{quantile="0.99"} 10000.0
        my_summary{quantile="0.999"} 10000.0
        my_summary_count 5
        my_summary_sum 10130.0
        my_summary{quantile="0.01", myValue="labels"} 123.0
        my_summary{quantile="0.05", myValue="labels"} 123.0
        my_summary{quantile="0.5", myValue="labels"} 123.0
        my_summary{quantile="0.9", myValue="labels"} 123.0
        my_summary{quantile="0.95", myValue="labels"} 123.0
        my_summary{quantile="0.99", myValue="labels"} 123.0
        my_summary{quantile="0.999", myValue="labels"} 123.0
        my_summary_count{myValue="labels"} 1
        my_summary_sum{myValue="labels"} 123.0
        """)
    }
    
    func testSummaryWithPreferredDisplayUnit() {
        let summary = Timer(label: "my_summary", preferredDisplayUnit: .seconds)
        
        summary.recordSeconds(1)
        summary.recordMilliseconds(2 * 1_000)
        summary.recordNanoseconds(4 * 1_000_000_000)
        summary.recordSeconds(10000)

        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        
        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE my_summary summary
        my_summary{quantile="0.01"} 1.0
        my_summary{quantile="0.05"} 1.0
        my_summary{quantile="0.5"} 3.0
        my_summary{quantile="0.9"} 10000.0
        my_summary{quantile="0.95"} 10000.0
        my_summary{quantile="0.99"} 10000.0
        my_summary{quantile="0.999"} 10000.0
        my_summary_count 4
        my_summary_sum 10007.0
        """)
    }
    
    func testMetricDestroying() {
        let counter = Counter(label: "my_counter")
        counter.increment()
        counter.destroy()
        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        
        XCTAssertEqual(try! promise.futureResult.wait(), "")
    }
    
    func testCollectIntoBuffer() {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterTwo = Counter(label: "my_counter", dimensions: [("myValue", "labels")])
        counterTwo.increment(by: 10)
        
        let promise = self.eventLoop.makePromise(of: ByteBuffer.self)
        prom.collect(promise.succeed)
        var buffer = try! promise.futureResult.wait()
        
        XCTAssertEqual(buffer.readString(length: buffer.readableBytes), """
        # TYPE my_counter counter
        my_counter 10
        my_counter{myValue=\"labels\"} 10\n
        """)
    }

    func testCollectAFewMetricsIntoBuffer() {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterA = Counter(label: "my_counter", dimensions: [("a", "aaa"), ("x", "x")])
        counterA.increment(by: 4)
        let gauge = Gauge(label: "my_gauge")
        gauge.record(100)

        let promise = self.eventLoop.makePromise(of: ByteBuffer.self)
        prom.collect(promise.succeed)
        var buffer = try! promise.futureResult.wait()

        XCTAssertEqual(buffer.readString(length: buffer.readableBytes),
            """
            # TYPE my_counter counter
            my_counter 10
            my_counter{x="x", a="aaa"} 4
            # TYPE my_gauge gauge
            my_gauge 100.0\n
            """)
    }

    func testCollectAFewMetricsIntoString() {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterA = Counter(label: "my_counter", dimensions: [("a", "aaa"), ("x", "x")])
        counterA.increment(by: 4)
        let gauge = Gauge(label: "my_gauge")
        gauge.record(100)

        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        let string = try! promise.futureResult.wait()

        XCTAssertEqual(string,
            """
            # TYPE my_counter counter
            my_counter 10
            my_counter{x="x", a="aaa"} 4
            # TYPE my_gauge gauge
            my_gauge 100.0
            """)
    }
}

