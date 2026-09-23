//
//  KitoPasswordStrengthMeter.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI

/// A four-segment strength bar with a label, and optionally the policy's requirement
/// checklist, ticking live as the person types.
///
/// ```swift
/// SecureField("Password", text: $password)
/// KitoPasswordStrengthMeter(password: password, policy: .standard)
/// ```
public struct KitoPasswordStrengthMeter: View {
    let password: String
    let policy: KitoPasswordPolicy
    var showsChecklist: Bool

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(password: String, policy: KitoPasswordPolicy = .standard, showsChecklist: Bool = true) {
        self.password = password
        self.policy = policy
        self.showsChecklist = showsChecklist
    }

    private var evaluation: KitoPasswordEvaluation { policy.evaluate(password) }

    private func color(for strength: KitoPasswordStrength) -> Color {
        switch strength {
        case .empty: return theme.colors.border
        case .weak: return theme.colors.danger
        case .fair: return theme.colors.warning
        case .good: return theme.colors.success.opacity(0.8)
        case .strong: return theme.colors.success
        }
    }

    public var body: some View {
        let evaluation = evaluation
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(spacing: theme.spacing.md) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(0..<4, id: \.self) { index in
                        let lit = index < evaluation.strength.filledSegments
                        Capsule()
                            .fill(theme.colors.surfaceMuted)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(color(for: evaluation.strength).gradient)
                                        .frame(width: lit ? proxy.size.width : 0)
                                }
                            }
                            .clipShape(Capsule())
                            .frame(height: 6)
                            .animation(reduceMotion ? .easeInOut(duration: 0.15)
                                       : .spring(duration: 0.45, bounce: 0.3).delay(Double(index) * 0.05),
                                       value: evaluation.strength)
                    }
                }
                Text(evaluation.strength.title)
                    .font(theme.typography.label)
                    .foregroundStyle(color(for: evaluation.strength))
                    .frame(width: 56, alignment: .trailing)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: evaluation.strength)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Password strength")
            .accessibilityValue(evaluation.strength == .empty ? "No password" : evaluation.strength.title)

            if showsChecklist {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    ForEach(policy.rules) { rule in
                        ChecklistRow(title: rule.title, isMet: evaluation.satisfiedRuleIDs.contains(rule.id))
                    }
                }
            }
        }
    }
}

/// One requirement: a circle that morphs into a tick when met.
struct ChecklistRow: View {
    let title: String
    let isMet: Bool
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isMet ? theme.colors.success : theme.colors.onBackground.opacity(0.3))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isMet)
            Text(title)
                .font(theme.typography.label)
                .foregroundStyle(isMet ? theme.colors.onBackground : theme.colors.onBackground.opacity(0.55))
        }
        .animation(.spring(duration: 0.3), value: isMet)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMet ? "Met" : "Not met")
    }
}
