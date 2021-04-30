import XCTest
import NIO
@testable import Prometheus
@testable import CoreMetrics

final class SanitizerTests: XCTestCase {
    
    var group: EventLoopGroup!
    var eventLoop: EventLoop {
        return group.next()
    }
    
    override func setUp() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    override func tearDown() {
        try! self.group.syncShutdownGracefully()
    }
    
    func testDefaultSanitizer() throws {
        let sanitizer = PrometheusLabelSanitizer()
        
        XCTAssertEqual(sanitizer.sanitize("MyMetrics.RequestDuration"), "mymetrics_requestduration")
        XCTAssertEqual(sanitizer.sanitize("My-Metrics.request-Duration"), "my_metrics_request_duration")
    }
    
    func testCustomSanitizer() throws {
        struct Sanitizer: LabelSanitizer {
            func sanitize(_ label: String) -> String {
                return String(label.reversed())
            }
        }
        
        let sanitizer = Sanitizer()
        XCTAssertEqual(sanitizer.sanitize("MyMetrics.RequestDuration"), "noitaruDtseuqeR.scirteMyM")
    }
    
    func testIntegratedSanitizer() throws {
        let prom = PrometheusClient()
        MetricsSystem.bootstrapInternal(PrometheusMetricsFactory(client: prom))
        
        CoreMetrics.Counter(label: "Test.Counter").increment(by: 10)
        
        let promise = eventLoop.makePromise(of: String.self)
        prom.collect(into: promise)
        XCTAssertEqual(try! promise.futureResult.wait(), """
        # TYPE test_counter counter
        test_counter 10\n
        """)
    }
}
