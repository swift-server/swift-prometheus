import XCTest
@testable import SwiftPrometheus

final class SwiftPrometheusTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(SwiftPrometheus().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
