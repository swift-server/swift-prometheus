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

public final class Gauge: Sendable {
    let atomic = ManagedAtomic(Double.zero.bitPattern)

    let name: String
    let labels: [(String, String)]
    let prerenderedExport: [UInt8]

    init(name: String, labels: [(String, String)]) {
        self.name = name
        self.labels = labels
        
        var prerendered = [UInt8]()
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

    public func set(to value: Double) {
        self.atomic.store(value.bitPattern, ordering: .relaxed)
    }

    public func increment(by amount: Double = 1.0) {
        // We busy loop here until we can update the atomic successfully.
        // Using relaxed ordering here is sufficient, since the as-if rules guarantess that
        // the following operations are executed in the order presented here. Every statement
        // depends on the execution before.
        while true {
            let bits = self.atomic.load(ordering: .relaxed)
            let value = Double(bitPattern: bits) + amount
            let (exchanged, _) = self.atomic.compareExchange(expected: bits, desired: value.bitPattern, ordering: .relaxed)
            if exchanged {
                break
            }
        }
    }

    public func decrement(by amount: Double = 1.0) {
        self.increment(by: -amount)
    }
}

extension Gauge: CoreMetrics.RecorderHandler {
    public func record(_ value: Int64) {
        self.record(Double(value))
    }

    public func record(_ value: Double) {
        self.set(to: value)
    }
}

extension Gauge: PrometheusMetric {
    func emit(into buffer: inout [UInt8]) {
        let value = Double(bitPattern: self.atomic.load(ordering: .relaxed))

        buffer.append(contentsOf: self.prerenderedExport)
        buffer.append(contentsOf: "\(value)".utf8)
        buffer.append(UInt8(ascii: "\n"))
    }
}
