//
//  NIOLock.swift
//  SwiftGodot
//

import Foundation

@usableFromInline
final class LockStorage<Value>: @unchecked Sendable {
    @usableFromInline
    var value: Value

    @usableFromInline
    let underlyingLock = NSLock()

    @usableFromInline
    init(value: Value) {
        self.value = value
    }

    @inlinable
    static func create(value: Value) -> Self {
        Self(value: value)
    }

    @inlinable
    func lock() {
        underlyingLock.lock()
    }

    @inlinable
    func unlock() {
        underlyingLock.unlock()
    }

    @inlinable
    func withLockedValue<T>(_ mutate: (inout Value) throws -> T) rethrows -> T {
        underlyingLock.lock()
        defer {
            underlyingLock.unlock()
        }
        return try mutate(&value)
    }
}

/// A threading lock backed by Foundation's `NSLock`.
///
/// - Note: ``NIOLock`` has reference semantics.
@frozen public struct NIOLock {
    @usableFromInline
    internal let _storage: LockStorage<Void>

    /// Create a new lock.
    @inlinable
    public init() {
        self._storage = .create(value: ())
    }

    /// Acquire the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    @inlinable
    public func lock() {
        self._storage.lock()
    }

    /// Release the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `lock`, to simplify lock handling.
    @inlinable
    public func unlock() {
        self._storage.unlock()
    }
}

extension NIOLock {
    /// Acquire the lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    @inlinable
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try body()
    }

    @inlinable
    public func withLockVoid(_ body: () throws -> Void) rethrows {
        try self.withLock(body)
    }
}

extension NIOLock: @unchecked Sendable {}
