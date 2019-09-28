#if !canImport(ObjectiveC)
import XCTest

extension PrometheusMetricsTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PrometheusMetricsTests = [
        ("testCollectAFewMetricsIntoBuffer", testCollectAFewMetricsIntoBuffer),
        ("testCollectAFewMetricsIntoString", testCollectAFewMetricsIntoString),
        ("testCollectIntoBuffer", testCollectIntoBuffer),
        ("testCounter", testCounter),
        ("testGauge", testGauge),
        ("testHistogram", testHistogram),
        ("testMetricDestroying", testMetricDestroying),
        ("testSummary", testSummary),
    ]
}

extension SwiftPrometheusTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__SwiftPrometheusTests = [
        ("testCounter", testCounter),
        ("testGauge", testGauge),
        ("testHistogram", testHistogram),
        ("testSummary", testSummary),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(PrometheusMetricsTests.__allTests__PrometheusMetricsTests),
        testCase(SwiftPrometheusTests.__allTests__SwiftPrometheusTests),
    ]
}
#endif
