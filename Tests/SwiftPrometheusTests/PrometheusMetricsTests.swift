import XCTest
@testable import Prometheus
@testable import CoreMetrics

final class PrometheusMetricsTests: XCTestCase {
    
    var prom: PrometheusClient!
    
    override func setUp() {
        self.prom = PrometheusClient()
        MetricsSystem.bootstrapInternal(prom)
    }
    
    override func tearDown() {
        self.prom = nil
    }
    
    func testCounter() {
        let counter = Counter(label: "my_counter")
        counter.increment(by: 10)
        let counterTwo = Counter(label: "my_counter", dimensions: [("myValue", "labels")])
        counterTwo.increment(by: 10)

        XCTAssertEqual(prom.collect(), """
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

        XCTAssertEqual(prom.collect(), """
        # TYPE my_gauge gauge
        my_gauge 20.0
        my_gauge{myValue=\"labels\"} 10.0
        """)
    }

    func testHistogram() {
        let recorder = Recorder(label: "my_histogram")
        recorder.record(1)
        recorder.record(2)
        recorder.record(3)

        let recorderTwo = Recorder(label: "my_histogram", dimensions: [("myValue", "labels")])
        recorderTwo.record(3)

        XCTAssertEqual(prom.collect(), """
        # TYPE my_histogram histogram
        my_histogram_bucket{le="0.005"} 0.0
        my_histogram_bucket{le="0.01"} 0.0
        my_histogram_bucket{le="0.025"} 0.0
        my_histogram_bucket{le="0.05"} 0.0
        my_histogram_bucket{le="0.075"} 0.0
        my_histogram_bucket{le="0.1"} 0.0
        my_histogram_bucket{le="0.25"} 0.0
        my_histogram_bucket{le="0.5"} 0.0
        my_histogram_bucket{le="0.75"} 0.0
        my_histogram_bucket{le="1.0"} 1.0
        my_histogram_bucket{le="2.5"} 2.0
        my_histogram_bucket{le="5.0"} 4.0
        my_histogram_bucket{le="7.5"} 4.0
        my_histogram_bucket{le="10.0"} 4.0
        my_histogram_bucket{le="+Inf"} 4.0
        my_histogram_count 4.0
        my_histogram_sum 9.0
        my_histogram_bucket{myValue="labels", le="0.005"} 0.0
        my_histogram_bucket{myValue="labels", le="0.01"} 0.0
        my_histogram_bucket{myValue="labels", le="0.025"} 0.0
        my_histogram_bucket{myValue="labels", le="0.05"} 0.0
        my_histogram_bucket{myValue="labels", le="0.075"} 0.0
        my_histogram_bucket{myValue="labels", le="0.1"} 0.0
        my_histogram_bucket{myValue="labels", le="0.25"} 0.0
        my_histogram_bucket{myValue="labels", le="0.5"} 0.0
        my_histogram_bucket{myValue="labels", le="0.75"} 0.0
        my_histogram_bucket{myValue="labels", le="1.0"} 0.0
        my_histogram_bucket{myValue="labels", le="2.5"} 0.0
        my_histogram_bucket{myValue="labels", le="5.0"} 1.0
        my_histogram_bucket{myValue="labels", le="7.5"} 1.0
        my_histogram_bucket{myValue="labels", le="10.0"} 1.0
        my_histogram_bucket{myValue="labels", le="+Inf"} 1.0
        my_histogram_count{myValue="labels"} 1.0
        my_histogram_sum{myValue="labels"} 3.0
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
        
        XCTAssertEqual(prom.collect(), """
        # TYPE my_summary summary
        my_summary{quantile="0.01"} 1.0
        my_summary{quantile="0.05"} 1.0
        my_summary{quantile="0.5"} 4.0
        my_summary{quantile="0.9"} 10000.0
        my_summary{quantile="0.95"} 10000.0
        my_summary{quantile="0.99"} 10000.0
        my_summary{quantile="0.999"} 10000.0
        my_summary_count 5
        my_summary_sum 10130
        my_summary{quantile="0.01", myValue="labels"} 123.0
        my_summary{quantile="0.05", myValue="labels"} 123.0
        my_summary{quantile="0.5", myValue="labels"} 123.0
        my_summary{quantile="0.9", myValue="labels"} 123.0
        my_summary{quantile="0.95", myValue="labels"} 123.0
        my_summary{quantile="0.99", myValue="labels"} 123.0
        my_summary{quantile="0.999", myValue="labels"} 123.0
        my_summary_count{myValue="labels"} 1
        my_summary_sum{myValue="labels"} 123
        """)
    }

    /// This is what you'd get with
    //     let start = Date()
    //     let oneSecond = -start.timeIntervalSince(start.addingTimeInterval(1.0))
    func testSummaryDouble() {
        let summary = Timer(label: "summary_seconds")

        summary.recordSeconds(1.0)
        summary.recordSeconds(2.0)
        summary.recordSeconds(4.0)
        summary.recordSeconds(10000.0)

        let summaryTwo = Timer(label: "summary_seconds", dimensions: [("myValue", "labels")])
        summaryTwo.recordSeconds(123.0)

        XCTAssertEqual(prom.collect(), """
        # TYPE summary_seconds summary
        summary_seconds{quantile="0.01"} 1.0
        summary_seconds{quantile="0.05"} 1.0
        summary_seconds{quantile="0.5"} 4.0
        summary_seconds{quantile="0.9"} 10000.0
        summary_seconds{quantile="0.95"} 10000.0
        summary_seconds{quantile="0.99"} 10000.0
        summary_seconds{quantile="0.999"} 10000.0
        summary_seconds_count 5
        summary_seconds_sum 10130
        summary_seconds{quantile="0.01", myValue="labels"} 123.0
        summary_seconds{quantile="0.05", myValue="labels"} 123.0
        summary_seconds{quantile="0.5", myValue="labels"} 123.0
        summary_seconds{quantile="0.9", myValue="labels"} 123.0
        summary_seconds{quantile="0.95", myValue="labels"} 123.0
        summary_seconds{quantile="0.99", myValue="labels"} 123.0
        summary_seconds{quantile="0.999", myValue="labels"} 123.0
        summary_seconds_count{myValue="labels"} 1
        summary_seconds_sum{myValue="labels"} 123
        """)
    }
    
    func testMetricDestroying() {
        let counter = Counter(label: "my_counter")
        counter.increment()
        counter.destroy()
        XCTAssertEqual(prom.collect(), "")
    }
}

