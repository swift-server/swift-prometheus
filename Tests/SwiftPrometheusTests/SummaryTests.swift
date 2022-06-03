import XCTest
import NIO
@testable import Prometheus
@testable import CoreMetrics

final class SummaryTests: XCTestCase {
    let baseLabels = DimensionLabels([("myValue", "labels")])
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
    
    func testSummary() {
        let summary = Timer(label: "my_summary")
        summary.handler.preferDisplayUnit(.nanoseconds)

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
        my_summary_sum{myValue="labels"} 123.0\n
        """)
    }

    func testConcurrent() throws {
        let prom = PrometheusClient()
        let summary = prom.createSummary(forType: Double.self, named: "my_summary",
                                             helpText: "Summary for testing")
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 8)
        let semaphore = DispatchSemaphore(value: 2)
        _ = elg.next().submit {
            for _ in 1...1_000 {
                let labels = DimensionLabels([("myValue", "1")])
                let labels2 = DimensionLabels([("myValue", "2")])

                summary.observe(1.0, labels)
                summary.observe(1.0, labels2)
            }
            semaphore.signal()
        }
        _ = elg.next().submit {
            for _ in 1...1_000 {
                let labels = DimensionLabels([("myValue", "1")])
                let labels2 = DimensionLabels([("myValue", "2")])

                summary.observe(1.0, labels2)
                summary.observe(1.0, labels)
            }
            semaphore.signal()
        }
        semaphore.wait()
        try elg.syncShutdownGracefully()
        XCTAssertTrue(summary.collect().contains("my_summary_count 4000.0"))
        XCTAssertTrue(summary.collect().contains("my_summary_sum 4000.0"))
    }
    
    func testSummaryWithPreferredDisplayUnit() {
        let summary = Timer(label: "my_summary", preferredDisplayUnit: .seconds)
        
        summary.recordSeconds(1)
        summary.recordMilliseconds(2 * 1_000)
        summary.recordMicroseconds(3 * 1_000_000)
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
        my_summary_count 5
        my_summary_sum 10010.0\n
        """)
    }
    
    func testSummaryTime() {
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99])
        let delay = 0.05
        summary.time {
            Thread.sleep(forTimeInterval: delay)
        }
        // This setup checks `.startsWith` on a per-line basis
        // to prevent issues with subsecond differences per test run
        let lines = [
            "# HELP my_summary Summary for testing",
            "# TYPE my_summary summary",
            #"my_summary{quantile="0.5"} 0.05"#,
            #"my_summary{quantile="0.9"} 0.05"#,
            #"my_summary{quantile="0.99"} 0.05"#,
            #"my_summary_count 1.0"#,
            #"my_summary_sum 0.05"#
        ]
        let collect = summary.collect()
        let sections = collect.split(separator: "\n").map(String.init).enumerated().map { i, s in s.starts(with: lines[i]) }
        XCTAssert(sections.filter { !$0 }.isEmpty)
    }
    
    func testSummaryStandalone() {
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99])
        let summaryTwo = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99])
        
        summary.observe(1)
        summary.observe(2)
        summary.observe(4)
        summaryTwo.observe(10000)
        
        summary.observe(123, baseLabels)
        
        XCTAssertEqual(summary.collect(), """
        # HELP my_summary Summary for testing
        # TYPE my_summary summary
        my_summary{quantile=\"0.5\"} 4.0
        my_summary{quantile=\"0.9\"} 10000.0
        my_summary{quantile=\"0.99\"} 10000.0
        my_summary_count 5.0
        my_summary_sum 10130.0
        my_summary{quantile=\"0.5\", myValue=\"labels\"} 123.0
        my_summary{quantile=\"0.9\", myValue=\"labels\"} 123.0
        my_summary{quantile=\"0.99\", myValue=\"labels\"} 123.0
        my_summary_count{myValue=\"labels\"} 1.0
        my_summary_sum{myValue=\"labels\"} 123.0
        """)
    }

    func testStandaloneSummaryWithCustomCapacity() {
        let capacity = 10
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", capacity: capacity, quantiles: [0.5, 0.99])

        for i in 0 ..< capacity { summary.observe(Double(i * 1_000)) }
        for i in 0 ..< capacity { summary.observe(Double(i)) }

        XCTAssertEqual(summary.collect(), """
        # HELP my_summary Summary for testing
        # TYPE my_summary summary
        my_summary{quantile="0.5"} 4.5
        my_summary{quantile="0.99"} 9.0
        my_summary_count 20.0
        my_summary_sum 45045.0
        """)
    }
}
