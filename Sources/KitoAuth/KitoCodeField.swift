//
//  KitoCodeField.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI
import UIKit

/// How a code field is drawn: normal, red after a wrong code, or green once accepted.
public enum KitoCodeFieldState: Equatable, Sendable {
    case editing, error, success
}

/// A row of animated digit boxes for one-time codes and PINs, 4 to 8 digits.
///
/// Supports typing, paste (a whole SMS works: "Your code is 123-456"), iOS SMS autofill via
/// `.oneTimeCode`, and VoiceOver, which reads it as one field ("3 of 6 digits entered").
/// `onComplete` fires once when the last digit arrives.
public struct KitoCodeField: View {
    @Binding var code: String
    let length: Int
    var state: KitoCodeFieldState
    var isSecure: Bool
    var tint: Color?
    var autoFocus: Bool
    var onComplete: ((String) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var caretVisible = true

    public init(code: Binding<String>, length: Int = 6, state: KitoCodeFieldState = .editing, isSecure: Bool = false,
                tint: Color? = nil, autoFocus: Bool = true, onComplete: ((String) -> Void)? = nil) {
        _code = code
        self.length = min(8, max(4, length))
        self.state = state
        self.isSecure = isSecure
        self.tint = tint
        self.autoFocus = autoFocus
        self.onComplete = onComplete
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var digits: [Character] { Array(code) }
    private var spacing: CGFloat { length > 6 ? theme.spacing.xs + 2 : theme.spacing.sm + 2 }

    public var body: some View {
        ZStack {
            boxes
            input
        }
        .frame(height: 64)
        .contentShape(Rectangle())
        .onTapGesture { if state != .success { focused = true } }
        .contextMenu {
            Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
        }
        .onAppear {
            if autoFocus && state != .success {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    focused = true
                }
            }
        }
        .task(id: focused) {
            guard focused, !reduceMotion else { caretVisible = true; return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                caretVisible.toggle()
            }
        }
    }

    private var boxes: some View {
        HStack(spacing: spacing) {
            ForEach(0..<length, id: \.self) { index in
                box(at: index)
            }
        }
        .accessibilityHidden(true)
    }

    private func box(at index: Int) -> some View {
        let filled = index < digits.count
        let active = focused && state == .editing && index == min(digits.count, length - 1) && digits.count < length
        let stroke: Color = {
            switch state {
            case .error: return theme.colors.danger
            case .success: return theme.colors.success
            case .editing: return active ? palette.accent : (filled ? palette.accent.opacity(0.35) : theme.colors.border)
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                .fill(state == .error ? theme.colors.danger.opacity(0.08)
                      : state == .success ? theme.colors.success.opacity(0.1) : theme.colors.surface)
            RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                .stroke(stroke, lineWidth: active || state != .editing ? 2 : 1)
            if filled {
                Group {
                    if isSecure {
                        Circle().fill(theme.colors.onSurface).frame(width: 12, height: 12)
                    } else {
                        Text(String(digits[index]))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(state == .error ? theme.colors.danger : theme.colors.onSurface)
                    }
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(y: 8)))
            } else if active {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 2, height: 24)
                    .opacity(caretVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: caretVisible)
            }
        }
        .frame(maxWidth: 56)
        .aspectRatio(0.84, contentMode: .fit)
        .scaleEffect(active && !reduceMotion ? 1.05 : 1)
        .shadow(color: active ? palette.accent.opacity(0.18) : .clear, radius: 8, y: 4)
        .animation(.authSpring(reduceMotion, bounce: 0.5), value: filled)
        .animation(.authSpring(reduceMotion), value: active)
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                   : .spring(duration: 0.4, bounce: 0.4).delay(state == .success ? Double(index) * 0.04 : 0), value: state)
    }

    /// The real text field sits on top, invisible, so autofill, paste and VoiceOver all work.
    private var input: some View {
        TextField("", text: Binding(get: { code }, set: { receive($0) }))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focused)
            .foregroundStyle(.clear)
            .tint(.clear)
            .font(.system(size: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .disabled(state == .success)
            .accessibilityLabel(isSecure ? "Passcode" : "Verification code")
            .accessibilityValue(state == .success ? "Accepted" : "\(digits.count) of \(length) digits entered")
            .accessibilityHint(state == .error ? "Incorrect code. Enter it again." : "")
    }

    private func receive(_ newValue: String) {
        let cleaned = KitoOTPCode.normalize(newValue, length: length)
        guard cleaned != code else { return }
        if cleaned.count > code.count { AuthHaptics.soft() }
        code = cleaned
        if cleaned.count == length {
            onComplete?(cleaned)
        }
    }

    private func paste() {
        guard let string = UIPasteboard.general.string else { return }
        receive(string)
    }
}
