import XCTest
import Prometheus
class BucketsTests: XCTestCase {
    func testExponentialDoesNotThrow() {
        let buckets = Buckets.exponential(start: 1, factor: 2, count: 4)
        XCTAssertEqual([1.0, 2.0, 4.0, 8.0, Double.greatestFiniteMagnitude], buckets.buckets)
    }

    func testLinearDoesNotThrow() {
        let buckets = Buckets.linear(start: 1, width: 20, count: 4)
        XCTAssertEqual([1, 21, 41, 61, Double.greatestFiniteMagnitude], buckets.buckets)
    }
}
