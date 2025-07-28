//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2018-2023 SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CoreMetrics

/// A type that can be used in a ``Histogram`` to create bucket boundaries
public protocol Bucketable: AdditiveArithmetic, Comparable, Sendable {
    /// A string representation that is used in the Prometheus export
    var bucketRepresentation: String { get }
}

/// A Histogram to record timings
public typealias DurationHistogram = Histogram<Duration>
/// A Histogram to record floating point values
public typealias ValueHistogram = Histogram<Double>

/// A generic Histogram implementation
public final class Histogram<Value: Bucketable>: Sendable {
    let name: String
    let labels: [(String, String)]

    @usableFromInline
    struct State: Sendable {
        @usableFromInline var buckets: [(Value, Int)]
        @usableFromInline var sum: Value
        @usableFromInline var count: Int

        @inlinable
        init(buckets: [Value]) {
            self.sum = .zero
            self.count = 0
            self.buckets = buckets.map { ($0, 0) }
        }
    }

    @usableFromInline let box: NIOLockedValueBox<State>
    let prerenderedLabels: [UInt8]?

    init(name: String, labels: [(String, String)], buckets: [Value]) {
        self.name = name
        self.labels = labels

        self.prerenderedLabels = Self.prerenderLabels(labels)

        self.box = .init(.init(buckets: buckets))
    }

    @inlinable
    public func record(_ value: Value) {
        self.box.withLockedValue { state in
            for i in state.buckets.startIndex..<state.buckets.endIndex {
                if state.buckets[i].0 >= value {
                    state.buckets[i].1 += 1
                }
            }
            state.sum += value
            state.count += 1
        }
    }
}

extension Histogram: _SwiftMetricsSendableProtocol {}

extension Histogram: CoreMetrics.TimerHandler where Value == Duration {
    public func recordNanoseconds(_ duration: Int64) {
        let value = Duration.nanoseconds(duration)
        self.record(value)
    }
}

extension Histogram: CoreMetrics.RecorderHandler where Value == Double {
    public func record(_ value: Int64) {
        self.record(Double(value))
    }
}

extension Histogram: PrometheusMetric {
    func emit(into buffer: inout [UInt8]) {
        let state = self.box.withLockedValue { $0 }

        for bucket in state.buckets {
            buffer.append(contentsOf: self.name.utf8)
            buffer.append(contentsOf: #"_bucket{"#.utf8)
            if let prerenderedLabels {
                buffer.append(contentsOf: prerenderedLabels)
                buffer.append(UInt8(ascii: #","#))
            }
            buffer.append(contentsOf: #"le=""#.utf8)
            buffer.append(contentsOf: "\(bucket.0.bucketRepresentation)".utf8)
            buffer.append(UInt8(ascii: #"""#))
            buffer.append(contentsOf: #"} "#.utf8)
            buffer.append(contentsOf: "\(bucket.1)".utf8)
            buffer.append(contentsOf: #"\#n"#.utf8)
        }

        // +Inf
        buffer.append(contentsOf: self.name.utf8)
        buffer.append(contentsOf: #"_bucket{"#.utf8)
        if let prerenderedLabels {
            buffer.append(contentsOf: prerenderedLabels)
            buffer.append(UInt8(ascii: ","))
        }
        buffer.append(contentsOf: #"le="+Inf"} "#.utf8)
        buffer.append(contentsOf: "\(state.count)".utf8)
        buffer.append(contentsOf: #"\#n"#.utf8)

        // sum
        buffer.append(contentsOf: self.name.utf8)
        buffer.append(contentsOf: #"_sum"#.utf8)
        if let prerenderedLabels {
            buffer.append(UInt8(ascii: "{"))
            buffer.append(contentsOf: prerenderedLabels)
            buffer.append(contentsOf: #"} "#.utf8)
        } else {
            buffer.append(UInt8(ascii: " "))
        }
        buffer.append(contentsOf: "\(state.sum.bucketRepresentation)".utf8)
        buffer.append(contentsOf: #"\#n"#.utf8)

        // count
        buffer.append(contentsOf: self.name.utf8)
        buffer.append(contentsOf: #"_count"#.utf8)
        if let prerenderedLabels {
            buffer.append(UInt8(ascii: "{"))
            buffer.append(contentsOf: prerenderedLabels)
            buffer.append(contentsOf: #"} "#.utf8)
        } else {
            buffer.append(UInt8(ascii: " "))
        }
        buffer.append(contentsOf: "\(state.count)".utf8)
        buffer.append(contentsOf: #"\#n"#.utf8)
    }
}

extension Duration: Bucketable {
    public var bucketRepresentation: String {
        let attos = String(unsafeUninitializedCapacity: 18) { buffer in
            var num = self.components.attoseconds

            var positions = 17
            var length: Int?
            while positions >= 0 {
                defer {
                    positions -= 1
                    num = num / 10
                }
                let remainder = num % 10

                if length != nil {
                    buffer[positions] = UInt8(ascii: "0") + UInt8(remainder)
                } else {
                    if remainder == 0 {
                        continue
                    }

                    length = positions + 1
                    buffer[positions] = UInt8(ascii: "0") + UInt8(remainder)
                }
            }

            if length == nil {
                buffer[0] = UInt8(ascii: "0")
                length = 1
            }

            return length!
        }
        return "\(self.components.seconds).\(attos)"
    }
}

extension Double: Bucketable {
    public var bucketRepresentation: String {
        self.description
    }
}
