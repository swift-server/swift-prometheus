//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftPrometheus open source project
//
// Copyright (c) 2023 SwiftPrometheus project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftPrometheus project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Provides locked access to `Value`.
///
/// - note: ``NIOLockedValueBox`` has reference semantics and holds the `Value`
///         alongside a lock behind a reference.
///
/// This is no different than creating a ``Lock`` and protecting all
/// accesses to a value using the lock. But it's easy to forget to actually
/// acquire/release the lock in the correct place. ``NIOLockedValueBox`` makes
/// that much easier.
@usableFromInline
struct NIOLockedValueBox<Value> {

    @usableFromInline
    internal let _storage: LockStorage<Value>

    /// Initialize the `Value`.
    @inlinable
    init(_ value: Value) {
        self._storage = .create(value: value)
    }

    /// Access the `Value`, allowing mutation of it.
    @inlinable
    func withLockedValue<T>(_ mutate: (inout Value) throws -> T) rethrows -> T {
        return try self._storage.withLockedValue(mutate)
    }
}

extension NIOLockedValueBox: Sendable where Value: Sendable {}
