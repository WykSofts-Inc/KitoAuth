//
//  KitoStepFlow.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A small forward/back state machine for multi-step flows. It remembers which way it last
/// moved so views can slide the right way, and it can't go back from the final step.
public struct KitoStepFlow<Step: Hashable>: Equatable {
    public enum Direction: Equatable, Sendable { case forward, backward }

    public let steps: [Step]
    public private(set) var index: Int
    public private(set) var direction: Direction = .forward

    /// Starts on the first of `steps`. Returns nil for an empty list.
    public init?(steps: [Step]) {
        guard !steps.isEmpty else { return nil }
        self.steps = steps
        self.index = 0
    }

    public var current: Step { steps[index] }
    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == steps.count - 1 }
    /// Back is allowed from any step except the first and the last (a "done" step).
    public var canGoBack: Bool { !isFirst && !isLast }
    /// 0…1, counting the current step as reached.
    public var progress: Double { Double(index + 1) / Double(steps.count) }

    /// Moves to the next step. Returns false on the last one.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLast else { return false }
        direction = .forward
        index += 1
        return true
    }

    /// Moves to the previous step. Returns false when `canGoBack` is false.
    @discardableResult
    public mutating func back() -> Bool {
        guard canGoBack else { return false }
        direction = .backward
        index -= 1
        return true
    }

    /// Jumps to `step` if it's in the flow, setting the direction from where it sits.
    @discardableResult
    public mutating func go(to step: Step) -> Bool {
        guard let target = steps.firstIndex(of: step) else { return false }
        direction = target >= index ? .forward : .backward
        index = target
        return true
    }

    public mutating func reset() {
        direction = .backward
        index = 0
    }
}

public extension KitoStepFlow where Step: CaseIterable {
    /// Every case, in declaration order.
    init() {
        self.steps = Array(Step.allCases)
        self.index = 0
    }
}
