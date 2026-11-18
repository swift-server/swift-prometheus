//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2018-2026 SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Configuration

extension PrometheusMetricsFactory {
    /// Configuration used when creating Swift Metrics histograms.
    public struct Configuration: Sendable {
        /// Default upper bounds for duration histograms, unless overridden for a label.
        public var defaultDurationHistogramBuckets: [Duration]

        /// Default upper bounds for value histograms, unless overridden for a label.
        public var defaultValueHistogramBuckets: [Double]

        /// Creates a configuration with the built-in default histogram buckets.
        public init() {
            self.defaultDurationHistogramBuckets = PrometheusMetricsFactory.builtInDurationHistogramBuckets
            self.defaultValueHistogramBuckets = PrometheusMetricsFactory.builtInValueHistogramBuckets
        }
    }
}

extension PrometheusMetricsFactory.Configuration {
    /// Creates a configuration by reading default histogram buckets.
    ///
    /// Values are arrays of strings containing finite, strictly increasing upper bounds:
    ///
    /// - `swift.prometheus.default.histogram.buckets`: Shared defaults for both histogram kinds.
    /// - `swift.prometheus.default.duration.histogram.buckets`: Duration-specific defaults, in seconds.
    /// - `swift.prometheus.default.value.histogram.buckets`: Value-specific defaults, in raw units.
    ///
    /// With `EnvironmentVariablesProvider`, the keys map to the corresponding uppercase names
    /// separated by underscores. The provider reads comma-separated values as string arrays.
    /// Missing specific values fall back to the shared value, then to the built-in defaults.
    /// Supplied values that cannot be read as string arrays throw an error.
    /// Bounds used for durations must also be nonnegative and representable as `Duration`.
    /// Values are read once; the configuration does not reload automatically.
    ///
    /// - Parameter config: The reader supplying values from application-selected providers.
    /// - Throws: An error if configuration cannot be read as string arrays or contains invalid bounds.
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    public init(config: ConfigReader) async throws {
        self.init()
        let sharedKey: ConfigKey = "swift.prometheus.default.histogram.buckets"
        let durationKey: ConfigKey = "swift.prometheus.default.duration.histogram.buckets"
        let valueKey: ConfigKey = "swift.prometheus.default.value.histogram.buckets"
        let expectedBounds = "a nonempty array of finite, strictly increasing bounds"

        // Optional synchronous reads treat type and provider errors as missing values.
        // Fetching preserves those errors while still allowing missing keys to use defaults.
        let shared = try await config.fetchStringArray(forKey: sharedKey)
        let duration = try await config.fetchStringArray(forKey: durationKey)
        let value = try await config.fetchStringArray(forKey: valueKey)

        let sharedValueBuckets = try Self.validateBuckets(
            shared,
            forKey: sharedKey,
            expected: expectedBounds,
            parse: Self.parseValueHistogramBuckets
        )
        self.defaultDurationHistogramBuckets =
            try Self.validateBuckets(
                duration ?? shared,
                forKey: duration == nil ? sharedKey : durationKey,
                expected: "\(expectedBounds) in seconds, nonnegative and representable as Duration",
                parse: Self.parseDurationHistogramBuckets
            ) ?? self.defaultDurationHistogramBuckets
        self.defaultValueHistogramBuckets =
            try Self.validateBuckets(
                value,
                forKey: valueKey,
                expected: expectedBounds,
                parse: Self.parseValueHistogramBuckets
            ) ?? sharedValueBuckets ?? self.defaultValueHistogramBuckets
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    private static func validateBuckets<Bucket>(
        _ strings: [String]?,
        forKey key: ConfigKey,
        expected: String,
        parse: ([String]) -> [Bucket]?
    ) throws -> [Bucket]? {
        guard let strings else { return nil }
        guard let buckets = parse(strings) else {
            throw InvalidHistogramBuckets(key: key.description, expected: expected)
        }
        return buckets
    }

    private struct InvalidHistogramBuckets: Error, CustomStringConvertible {
        let key: String
        let expected: String

        var description: String { "Invalid histogram buckets for '\(key)': expected \(expected)." }
    }

    /// Parses histogram bucket upper bounds supplied by a configuration provider.
    ///
    /// Whitespace around values is ignored. Returns `nil` if the list is empty or contains empty
    /// elements, if a value can not be parsed as a finite `Double`, or if the values are not
    /// strictly increasing.
    static func parseValueHistogramBuckets(_ strings: [String]) -> [Double]? {
        var buckets = [Double]()
        for string in strings {
            var segment = string[...]
            while segment.first?.isWhitespace == true {
                segment.removeFirst()
            }
            while segment.last?.isWhitespace == true {
                segment.removeLast()
            }
            guard let bucket = Double(segment), bucket.isFinite else {
                return nil
            }
            if let last = buckets.last, bucket <= last {
                return nil
            }
            buckets.append(bucket)
        }
        return buckets.isEmpty ? nil : buckets
    }

    /// Parses duration histogram bucket upper bounds in seconds.
    ///
    /// In addition to the rules of ``parseValueHistogramBuckets(_:)``, every value must be zero
    /// or greater and representable as a `Duration`.
    static func parseDurationHistogramBuckets(_ strings: [String]) -> [Duration]? {
        guard let seconds = self.parseValueHistogramBuckets(strings) else {
            return nil
        }
        var buckets = [Duration]()
        for value in seconds {
            // `Duration` counts attoseconds in an Int128; converting a `Double` beyond its range traps.
            guard value >= 0, value * 1e18 < 0x1p127 else {
                return nil
            }
            buckets.append(.seconds(value))
        }
        return buckets
    }
}
