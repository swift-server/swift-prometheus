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

import Atomics
import CoreMetrics

/// A counter is a cumulative metric that represents a single monotonically increasing
/// counter whose value can only increase or be ``reset()`` to zero on restart.
///
/// For example, you can use a counter to represent the number of requests served, tasks completed, or errors.
///
/// Do not use a counter to expose a value that can decrease. For example, do not use a counter for the
/// number of currently running processes; instead use a ``Gauge``.
public final class Counter: Sendable {
    private let intAtomic = ManagedAtomic(Int64(0))
    private let floatAtomic = ManagedAtomic(Double(0).bitPattern)

    let name: String
    let labels: [(String, String)]
    private let prerenderedExport: [UInt8]

    init(name: String, labels: [(String, String)]) {
        self.name = name
        self.labels = labels

        var prerendered = [UInt8]()
        // 64 bytes is a good tradeoff to prevent reallocs lots of reallocs when appending names
        // and memory footprint.
        prerendered.reserveCapacity(64)
        prerendered.append(contentsOf: name.utf8)
        if let prerenderedLabels = Self.prerenderLabels(labels) {
            prerendered.append(UInt8(ascii: "{"))
            prerendered.append(contentsOf: prerenderedLabels)
            prerendered.append(contentsOf: #"} "#.utf8)
        } else {
            prerendered.append(UInt8(ascii: " "))
        }

        self.prerenderedExport = prerendered
    }

    public func increment() {
        self.increment(by: Int64(1))
    }

    public func increment(by amount: Int64) {
        precondition(amount >= 0)
        self.intAtomic.wrappingIncrement(by: amount, ordering: .relaxed)
    }

    public func increment(by amount: Double) {
        precondition(amount >= 0)
        // We busy loop here until we can update the atomic successfully.
        // Using relaxed ordering here is sufficient, since the as-if rules guarantess that
        // the following operations are executed in the order presented here. Every statement
        // depends on the execution before.
        while true {
            let bits = self.floatAtomic.load(ordering: .relaxed)
            let value = Double(bitPattern: bits) + amount
            let (exchanged, _) = self.floatAtomic.compareExchange(
                expected: bits,
                desired: value.bitPattern,
                ordering: .relaxed
            )
            if exchanged {
                break
            }
        }
    }

    public func reset() {
        self.intAtomic.store(0, ordering: .relaxed)
        self.floatAtomic.store(Double.zero.bitPattern, ordering: .relaxed)
    }
}

extension Counter: CoreMetrics.CounterHandler {}
extension Counter: CoreMetrics.FloatingPointCounterHandler {}

extension Counter: PrometheusMetric {
    func emit(into buffer: inout [UInt8]) {
        buffer.append(contentsOf: self.prerenderedExport)
        let doubleValue = Double(bitPattern: self.floatAtomic.load(ordering: .relaxed))
        let intValue = self.intAtomic.load(ordering: .relaxed)
        if doubleValue == .zero {
            buffer.append(contentsOf: "\(intValue)".utf8)
        } else {
            buffer.append(contentsOf: "\(doubleValue + Double(intValue))".utf8)
        }
        buffer.append(UInt8(ascii: "\n"))
    }
}
