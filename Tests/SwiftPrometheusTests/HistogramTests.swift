import XCTest
import NIO
@testable import Prometheus
@testable import CoreMetrics

final class HistogramTests: XCTestCase {
    struct BaseHistogramLabels: HistogramLabels {
        var le: String = ""
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

    func testConcurrent() throws {
        let prom = PrometheusClient()
        let histogram = prom.createHistogram(forType: Double.self, named: "my_histogram",
                                             helpText: "Histogram for testing",
                                             buckets: Buckets.exponential(start: 1, factor: 2, count: 63),
                                             labels: DimensionHistogramLabels.self)
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 8)
        let semaphore = DispatchSemaphore(value: 2)
        _ = elg.next().submit {
            for _ in 1...1_000 {
                let labels = DimensionHistogramLabels([("myValue", "1")])
                let labels2 = DimensionHistogramLabels([("myValue", "2")])

                histogram.observe(1.0, labels)
                histogram.observe(1.0, labels2)
            }
            semaphore.signal()
        }
        _ = elg.next().submit {
            for _ in 1...1_000 {
                let labels = DimensionHistogramLabels([("myValue", "1")])
                let labels2 = DimensionHistogramLabels([("myValue", "2")])

                histogram.observe(1.0, labels2)
                histogram.observe(1.0, labels)
            }
            semaphore.signal()
        }
        semaphore.wait()
        try elg.syncShutdownGracefully()
        XCTAssertTrue(histogram.collect().contains("my_histogram_count 4000.0"))
        XCTAssertTrue(histogram.collect().contains("my_histogram_sum 4000.0"))
    }
    
    func testHistogramSwiftMetrics() {
        let recorder = Recorder(label: "my_histogram")
        recorder.record(1)
        recorder.record(2)
        recorder.record(3)

        let recorderTwo = Recorder(label: "my_histogram", dimensions: [("myValue", "labels")])
        recorderTwo.record(3)

        let promise = self.eventLoop.makePromise(of: String.self)
        prom.collect(promise.succeed)
        
        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE my_histogram histogram
        my_histogram_bucket{le="0.005"} 0.0
        my_histogram_bucket{le="0.01"} 0.0
        my_histogram_bucket{le="0.025"} 0.0
        my_histogram_bucket{le="0.05"} 0.0
        my_histogram_bucket{le="0.1"} 0.0
        my_histogram_bucket{le="0.25"} 0.0
        my_histogram_bucket{le="0.5"} 0.0
        my_histogram_bucket{le="1.0"} 1.0
        my_histogram_bucket{le="2.5"} 2.0
        my_histogram_bucket{le="5.0"} 4.0
        my_histogram_bucket{le="10.0"} 4.0
        my_histogram_bucket{le="+Inf"} 4.0
        my_histogram_count 4.0
        my_histogram_sum 9.0
        my_histogram_bucket{myValue="labels", le="0.005"} 0.0
        my_histogram_bucket{myValue="labels", le="0.01"} 0.0
        my_histogram_bucket{myValue="labels", le="0.025"} 0.0
        my_histogram_bucket{myValue="labels", le="0.05"} 0.0
        my_histogram_bucket{myValue="labels", le="0.1"} 0.0
        my_histogram_bucket{myValue="labels", le="0.25"} 0.0
        my_histogram_bucket{myValue="labels", le="0.5"} 0.0
        my_histogram_bucket{myValue="labels", le="1.0"} 0.0
        my_histogram_bucket{myValue="labels", le="2.5"} 0.0
        my_histogram_bucket{myValue="labels", le="5.0"} 1.0
        my_histogram_bucket{myValue="labels", le="10.0"} 1.0
        my_histogram_bucket{myValue="labels", le="+Inf"} 1.0
        my_histogram_count{myValue="labels"} 1.0
        my_histogram_sum{myValue="labels"} 3.0\n
        """)
    }
    
    func testHistogramTime() {
        let histogram = prom.createHistogram(forType: Double.self, named: "my_histogram")
        let delay = 0.05
        histogram.time {
            Thread.sleep(forTimeInterval: delay)
        }
        // Using starts(with:) here since the exact subseconds might differ per-test.
        XCTAssert(histogram.collect().starts(with: """
        # TYPE my_histogram histogram
        my_histogram_bucket{le="0.005"} 0.0
        my_histogram_bucket{le="0.01"} 0.0
        my_histogram_bucket{le="0.025"} 0.0
        my_histogram_bucket{le="0.05"} 0.0
        my_histogram_bucket{le="0.1"} 1.0
        my_histogram_bucket{le="0.25"} 1.0
        my_histogram_bucket{le="0.5"} 1.0
        my_histogram_bucket{le="1.0"} 1.0
        my_histogram_bucket{le="2.5"} 1.0
        my_histogram_bucket{le="5.0"} 1.0
        my_histogram_bucket{le="10.0"} 1.0
        my_histogram_bucket{le="+Inf"} 1.0
        my_histogram_count 1.0
        my_histogram_sum 0.05
        """))
    }
    
    func testHistogramStandalone() {
        let histogram = prom.createHistogram(forType: Double.self, named: "my_histogram", helpText: "Histogram for testing", buckets: [0.5, 1, 2, 3, 5, Double.greatestFiniteMagnitude], labels: BaseHistogramLabels.self)
        let histogramTwo = prom.createHistogram(forType: Double.self, named: "my_histogram", helpText: "Histogram for testing", buckets: [0.5, 1, 2, 3, 5, Double.greatestFiniteMagnitude], labels: BaseHistogramLabels.self)

        histogram.observe(1)
        histogram.observe(2)
        histogramTwo.observe(3)
        
        histogram.observe(3, .init(myValue: "labels"))

        XCTAssertEqual(histogram.collect(), """
        # HELP my_histogram Histogram for testing
        # TYPE my_histogram histogram
        my_histogram_bucket{myValue="*", le="0.5"} 0.0
        my_histogram_bucket{myValue="*", le="1.0"} 1.0
        my_histogram_bucket{myValue="*", le="2.0"} 2.0
        my_histogram_bucket{myValue="*", le="3.0"} 4.0
        my_histogram_bucket{myValue="*", le="5.0"} 4.0
        my_histogram_bucket{myValue="*", le="+Inf"} 4.0
        my_histogram_count{myValue="*"} 4.0
        my_histogram_sum{myValue="*"} 9.0
        my_histogram_bucket{myValue="labels", le="0.5"} 0.0
        my_histogram_bucket{myValue="labels", le="1.0"} 0.0
        my_histogram_bucket{myValue="labels", le="2.0"} 0.0
        my_histogram_bucket{myValue="labels", le="3.0"} 1.0
        my_histogram_bucket{myValue="labels", le="5.0"} 1.0
        my_histogram_bucket{myValue="labels", le="+Inf"} 1.0
        my_histogram_count{myValue="labels"} 1.0
        my_histogram_sum{myValue="labels"} 3.0
        """)
    }
}
