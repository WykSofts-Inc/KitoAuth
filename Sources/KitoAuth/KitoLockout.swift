//
//  KitoLockout.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// How many wrong PINs are allowed before a wait, and how long each wait lasts.
/// Waits escalate: the first lockout uses `lockoutDurations[0]`, the next `[1]`, and so on,
/// staying on the last one.
public struct KitoLockoutPolicy: Equatable, Codable, Sendable {
    public var maxAttempts: Int
    public var lockoutDurations: [TimeInterval]

    public init(maxAttempts: Int = 5, lockoutDurations: [TimeInterval] = [30, 60, 300, 900]) {
        self.maxAttempts = max(1, maxAttempts)
        self.lockoutDurations = lockoutDurations.isEmpty ? [30] : lockoutDurations
    }

    /// The wait after the `index`th lockout (0-based).
    public func duration(forLockout index: Int) -> TimeInterval {
        guard !lockoutDurations.isEmpty else { return 30 }
        return lockoutDurations[min(max(0, index), lockoutDurations.count - 1)]
    }
}

/// Tracks wrong attempts against a `KitoLockoutPolicy`. Value type, so you can persist it.
public struct KitoLockoutState: Equatable, Codable, Sendable {
    public let policy: KitoLockoutPolicy
    public private(set) var failedAttempts = 0
    public private(set) var lockoutCount = 0
    public private(set) var lockedUntil: Date?

    public init(policy: KitoLockoutPolicy = KitoLockoutPolicy()) {
        self.policy = policy
    }

    /// Attempts left before the next lockout.
    public var attemptsRemaining: Int { max(0, policy.maxAttempts - failedAttempts) }

    public func isLocked(at date: Date = Date()) -> Bool {
        guard let lockedUntil else { return false }
        return date < lockedUntil
    }

    /// Seconds left in the current lockout, or 0.
    public func remaining(at date: Date = Date()) -> TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSince(date))
    }

    /// Records a wrong attempt. Returns true when this attempt started a lockout.
    /// Attempts made while locked are ignored.
    @discardableResult
    public mutating func recordFailure(at date: Date = Date()) -> Bool {
        guard !isLocked(at: date) else { return false }
        failedAttempts += 1
        guard failedAttempts >= policy.maxAttempts else { return false }
        lockedUntil = date.addingTimeInterval(policy.duration(forLockout: lockoutCount))
        lockoutCount += 1
        failedAttempts = 0
        return true
    }

    /// A correct attempt clears everything.
    public mutating func recordSuccess() {
        failedAttempts = 0
        lockoutCount = 0
        lockedUntil = nil
    }
}
