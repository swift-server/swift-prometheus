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

public protocol Bucketable: AdditiveArithmetic, Comparable {
    var bucketRepresentation: String { get }
}

public typealias TimeHistogram = Histogram<Duration>
public typealias ValueHistogram = Histogram<Double>

public final class Histogram<Value: Bucketable>: @unchecked Sendable {
    private let lock = NIOLock()

    let name: String
    let labels: [(String, String)]

    private var _buckets: [(Value, Int)]
    private var _sum: Value
    private var _count: Int

    private let prerenderedLabels: [UInt8]?

    init(name: String, labels: [(String, String)], buckets: [Value]) {
        self.name = name
        self.labels = labels

        self.prerenderedLabels = Self.prerenderLabels(labels)

        self._buckets = buckets.map { ($0, 0) }
        self._sum = .zero
        self._count = 0
    }

    public func record(_ value: Value) {
        self.lock.withLock {
            for i in self._buckets.startIndex..<self._buckets.endIndex {
                if self._buckets[i].0 >= value {
                    self._buckets[i].1 += 1
                }
            }
            self._sum += value
            self._count += 1
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
        let (buckets, sum, count) = self.lock.withLock { (self._buckets, self._sum, self._count) }

        for bucket in buckets {
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
        buffer.append(contentsOf: "\(count)".utf8)
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
        buffer.append(contentsOf: "\(sum.bucketRepresentation)".utf8)
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
        buffer.append(contentsOf: "\(count)".utf8)
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
