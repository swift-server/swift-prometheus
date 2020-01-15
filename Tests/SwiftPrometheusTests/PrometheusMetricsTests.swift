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

