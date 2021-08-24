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
        MetricsSystem.bootstrapInternal(PrometheusMetricsFactory(client: prom))
    }
    
    override func tearDown() {
        self.prom = nil
        try! self.group.syncShutdownGracefully()
    }

    func testGetPrometheus() {
        MetricsSystem.bootstrapInternal(NOOPMetricsHandler.instance)
        XCTAssertThrowsError(try MetricsSystem.prometheus())
        MetricsSystem.bootstrapInternal(PrometheusMetricsFactory(client: self.prom))
        XCTAssertNoThrow(try MetricsSystem.prometheus())
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
        my_counter{myValue=\"labels\"} 10\n
        """)
    }

    func testFloatingPointCounter() {
        let counter = FloatingPointCounter(label: "my_fp_counter")
        counter.increment(by: 3.5)
        let counterTwo = FloatingPointCounter(label: "my_fp_counter", dimensions: [("myValue", "labels")])
        counterTwo.increment(by: 10.4)

        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)

        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE my_fp_counter counter
        my_fp_counter 3.5
        my_fp_counter{myValue=\"labels\"} 10.4\n
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

    func testEmptyCollectIsConsistent() throws {
        let promise = self.eventLoop.makePromise(of: ByteBuffer.self)
        prom.collect(promise.succeed)
        var buffer = try promise.futureResult.wait()

        let stringPromise = self.eventLoop.makePromise(of: String.self)
        prom.collect(stringPromise.succeed)
        let collectedToString = try stringPromise.futureResult.wait()

        let collectedToBuffer = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(collectedToBuffer, "")
        XCTAssertEqual(collectedToBuffer, collectedToString)
    }

    func testCollectIsConsistent() throws {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterTwo = Counter(label: "my_counter", dimensions: [("myValue", "labels")])
        counterTwo.increment(by: 10)

        let promise = self.eventLoop.makePromise(of: ByteBuffer.self)
        prom.collect(promise.succeed)
        var buffer = try promise.futureResult.wait()

        let stringPromise = self.eventLoop.makePromise(of: String.self)
        prom.collect(stringPromise.succeed)
        let collectedToString = try stringPromise.futureResult.wait()

        let collectedToBuffer = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(collectedToBuffer, """
        # TYPE my_counter counter
        my_counter 10
        my_counter{myValue=\"labels\"} 10\n
        """)
        XCTAssertEqual(collectedToBuffer, collectedToString)
    }

    func testCollectAFewMetricsIntoBuffer() throws {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterA = Counter(label: "my_counter", dimensions: [("a", "aaa"), ("x", "x")])
        counterA.increment(by: 4)
        let gauge = Gauge(label: "my_gauge")
        gauge.record(100)

        let promise = self.eventLoop.makePromise(of: ByteBuffer.self)
        prom.collect(promise.succeed)
        var buffer = try promise.futureResult.wait()

        let collected = buffer.readString(length: buffer.readableBytes)!

        // We can't guarantee order so check the output contains the expected metrics.
        XCTAssertTrue(collected.contains("""
                                         # TYPE my_counter counter
                                         my_counter 10
                                         my_counter{x="x", a="aaa"} 4
                                         """))

        XCTAssertTrue(collected.contains("""
                                         # TYPE my_gauge gauge
                                         my_gauge 100.0
                                         """))
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
        let collected = try! promise.futureResult.wait()

        // We can't guarantee order so check the output contains the expected metrics.
        XCTAssertTrue(collected.contains("""
                                         # TYPE my_counter counter
                                         my_counter 10
                                         my_counter{x="x", a="aaa"} 4
                                         """))

        XCTAssertTrue(collected.contains("""
                                         # TYPE my_gauge gauge
                                         my_gauge 100.0
                                         """))
    }

    func testHistogramBackedTimer() {
        let prom = PrometheusClient()
        var config = PrometheusMetricsFactory.Configuration()
        config.timerImplementation = .histogram()
        let metricsFactory = PrometheusMetricsFactory(client: prom, configuration: config)
        metricsFactory.makeTimer(label: "duration_nanos", dimensions: []).recordNanoseconds(1)
        guard let histogram: PromHistogram<Int64, DimensionHistogramLabels> = prom.getMetricInstance(with: "duration_nanos", andType: .histogram) else {
            XCTFail("Timer should be backed by Histogram")
            return
        }
        let result = histogram.collect()
        let buckets = result.split(separator: "\n").filter { $0.contains("duration_nanos_bucket") }
        XCTAssertFalse(buckets.isEmpty, "default histogram backed timer buckets")
    }

    func testDestroyHistogramTimer() {
        let prom = PrometheusClient()
        var config = PrometheusMetricsFactory.Configuration()
        config.timerImplementation = .histogram()
        let metricsFactory = PrometheusMetricsFactory(client: prom, configuration: config)
        let timer = metricsFactory.makeTimer(label: "duration_nanos", dimensions: [])
        timer.recordNanoseconds(1)
        metricsFactory.destroyTimer(timer)
        let histogram: PromHistogram<Int64, DimensionHistogramLabels>? = prom.getMetricInstance(with: "duration_nanos", andType: .histogram)
        XCTAssertNil(histogram)
    }
    func testDestroySummaryTimer() {
        let prom = PrometheusClient()
        var config = PrometheusMetricsFactory.Configuration()
        config.timerImplementation = .summary()
        let metricsFactory = PrometheusMetricsFactory(client: prom)
        let timer = metricsFactory.makeTimer(label: "duration_nanos", dimensions: [])
        timer.recordNanoseconds(1)
        metricsFactory.destroyTimer(timer)
        let summary: PromSummary<Int64, DimensionSummaryLabels>? = prom.getMetricInstance(with: "duration_nanos", andType: .summary)
        XCTAssertNil(summary)
    }

    func testDimensionLabelEquality() {
        let labelsA = DimensionLabels([("a", "a")])
        let labelsB = DimensionLabels([("b", "b")])
        let labelsATwo = DimensionLabels([("a", "a")])

        XCTAssertEqual(labelsA, labelsATwo)
        XCTAssertNotEqual(labelsA, labelsB)
        XCTAssertNotEqual(labelsATwo, labelsB)
    }
}
