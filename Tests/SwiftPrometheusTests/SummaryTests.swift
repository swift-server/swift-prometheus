import XCTest
import NIO
@testable import Prometheus
@testable import CoreMetrics

final class SummaryTests: XCTestCase {
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
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        let delay = 0.051
        summary.time {
            Thread.sleep(forTimeInterval: delay)
        }
        // This setup checks `.startsWith` on a per-line basis
        // to prevent issues with subsecond differences per test run
        let lines = [
            "# HELP my_summary Summary for testing",
            "# TYPE my_summary summary",
            #"my_summary{quantile="0.5", myValue="*"} 0.05"#,
            #"my_summary{quantile="0.9", myValue="*"} 0.05"#,
            #"my_summary{quantile="0.99", myValue="*"} 0.05"#,
            #"my_summary_count{myValue="*"} 1.0"#,
            #"my_summary_sum{myValue="*"} 0.05"#
        ]
        let output = summary.collect()
        let sections = output.split(separator: "\n").map(String.init).enumerated().map { i, s in s.starts(with: lines[i]) }
        XCTAssert(sections.filter { !$0 }.isEmpty, output)
    }
    
    func testSummaryStandalone() {
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        let summaryTwo = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", quantiles: [0.5, 0.9, 0.99], labels: BaseSummaryLabels.self)
        
        summary.observe(1)
        summary.observe(2)
        summary.observe(4)
        summaryTwo.observe(10000)
        
        summary.observe(123, .init(myValue: "labels"))
        
        XCTAssertEqual(summary.collect(), """
        # HELP my_summary Summary for testing
        # TYPE my_summary summary
        my_summary{quantile=\"0.5\", myValue=\"*\"} 4.0
        my_summary{quantile=\"0.9\", myValue=\"*\"} 10000.0
        my_summary{quantile=\"0.99\", myValue=\"*\"} 10000.0
        my_summary_count{myValue=\"*\"} 5.0
        my_summary_sum{myValue=\"*\"} 10130.0
        my_summary{quantile=\"0.5\", myValue=\"labels\"} 123.0
        my_summary{quantile=\"0.9\", myValue=\"labels\"} 123.0
        my_summary{quantile=\"0.99\", myValue=\"labels\"} 123.0
        my_summary_count{myValue=\"labels\"} 1.0
        my_summary_sum{myValue=\"labels\"} 123.0
        """)
    }

    func testStandaloneSummaryWithCustomCapacity() {
        let capacity = 10
        let summary = prom.createSummary(forType: Double.self, named: "my_summary", helpText: "Summary for testing", capacity: capacity, quantiles: [0.5, 0.99], labels: BaseSummaryLabels.self)

        for i in 0 ..< capacity { summary.observe(Double(i * 1_000)) }
        for i in 0 ..< capacity { summary.observe(Double(i)) }

        XCTAssertEqual(summary.collect(), """
        # HELP my_summary Summary for testing
        # TYPE my_summary summary
        my_summary{quantile="0.5", myValue="*"} 4.5
        my_summary{quantile="0.99", myValue="*"} 9.0
        my_summary_count{myValue="*"} 20.0
        my_summary_sum{myValue="*"} 45045.0
        """)
    }
}
