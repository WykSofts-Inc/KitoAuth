//
//  KitoForgotPasswordFlow.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI

/// The steps of `KitoForgotPasswordFlow`, in order.
public enum KitoForgotPasswordStep: Hashable, CaseIterable, Sendable {
    case email, code, newPassword, done
}

/// Everything collected by the time the new password is submitted.
public struct KitoPasswordReset: Equatable, Sendable {
    public let email: String
    public let code: String
    public let newPassword: String
}

/// Reset a password in four animated steps: email, the emailed code, a new password with a live
/// strength meter and checklist, then done.
///
/// ```swift
/// KitoForgotPasswordFlow(email: typedEmail) { email in
///     try await api.sendResetCode(to: email); return .success
/// } verifyCode: { email, code in
///     try await api.checkResetCode(code, for: email) ? .success : .failure(message: "Wrong code")
/// } resetPassword: { reset in
///     try await api.resetPassword(reset.newPassword, code: reset.code, email: reset.email); return .success
/// }
/// .onFinish { dismiss() }
/// ```
public struct KitoForgotPasswordFlow: View {
    let initialEmail: String
    let codeLength: Int
    let policy: KitoPasswordPolicy
    var tint: Color?
    let sendCode: (String) async throws -> KitoAuthResult
    let verifyCode: (String, String) async throws -> KitoAuthResult
    let resetPassword: (KitoPasswordReset) async throws -> KitoAuthResult
    var finishHandler: (() -> Void)?
    var resendAfter = 30

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow = KitoStepFlow<KitoForgotPasswordStep>()
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var codeState: KitoCodeFieldState = .editing
    @State private var codeShakes = 0
    @State private var codeMessage: String?
    @State private var isCheckingCode = false
    @State private var runner = MorphRunner()
    @State private var deadline = Date()
    @State private var remaining = 0
    @State private var didStart = false

    public init(email: String = "", codeLength: Int = 6, policy: KitoPasswordPolicy = .standard, tint: Color? = nil,
                sendCode: @escaping (String) async throws -> KitoAuthResult,
                verifyCode: @escaping (_ email: String, _ code: String) async throws -> KitoAuthResult,
                resetPassword: @escaping (KitoPasswordReset) async throws -> KitoAuthResult) {
        self.initialEmail = email
        self.codeLength = min(8, max(4, codeLength))
        self.policy = policy
        self.tint = tint
        self.sendCode = sendCode
        self.verifyCode = verifyCode
        self.resetPassword = resetPassword
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty && !trimmedEmail.contains(" ")
    }
    private var evaluation: KitoPasswordEvaluation { policy.evaluate(password) }
    private var passwordsMatch: Bool { !confirmation.isEmpty && confirmation == password }

    public var body: some View {
        ZStack {
            AuthBackground(accent: palette.accent)
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    ZStack {
                        stepView(flow.current)
                            .id(flow.current)
                            .transition(stepTransition)
                    }
                    .padding(.horizontal, theme.spacing.xl)
                    .padding(.vertical, theme.spacing.xl)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            email = initialEmail
        }
        .task(id: deadline) {
            remaining = KitoCountdownFormat.secondsRemaining(until: deadline)
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining = KitoCountdownFormat.secondsRemaining(until: deadline)
            }
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let forward = flow.direction == .forward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: theme.spacing.md) {
            Button {
                AuthHaptics.tap()
                withAnimation(.authSpring(reduceMotion, bounce: 0.15)) { _ = flow.back() }
                runner.reset()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.onBackground)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.colors.surface))
                    .overlay(Circle().stroke(theme.colors.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .opacity(flow.canGoBack ? 1 : 0)
            .disabled(!flow.canGoBack)
            .accessibilityLabel("Back")

            StepIndicator(count: flow.steps.count, index: flow.index, accent: palette.accent)
                .frame(maxWidth: .infinity)

            Text("\(flow.index + 1)/\(flow.steps.count)")
                .font(theme.typography.label)
                .monospacedDigit()
                .foregroundStyle(theme.colors.onBackground.opacity(0.5))
                .frame(width: 40)
                .contentTransition(.numericText())
                .accessibilityLabel("Step \(flow.index + 1) of \(flow.steps.count)")
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.top, theme.spacing.md)
    }

    // MARK: Steps

    @ViewBuilder
    private func stepView(_ step: KitoForgotPasswordStep) -> some View {
        switch step {
        case .email: emailStep
        case .code: codeStep
        case .newPassword: passwordStep
        case .done: doneStep
        }
    }

    private var emailStep: some View {
        VStack(spacing: theme.spacing.xl) {
            AuthHeader(symbol: "lock.rotation", title: "Forgot password?",
                       subtitle: "Enter the email on your account and we’ll send you a code to reset it.", accent: palette.accent, onAccent: palette.onAccent)
            AuthTextField(title: "Email", symbol: "envelope", text: $email, contentType: .emailAddress,
                          keyboard: .emailAddress, accent: palette.accent, isInvalid: runner.message != nil)
                .onSubmit(sendTapped)
            InlineMessage(text: runner.message, color: theme.colors.danger)
            MorphButton(title: "Send code", systemImage: "paperplane.fill", phase: runner.phase, accent: palette.accent,
                        onAccent: palette.onAccent, isEnabled: emailLooksValid, shakes: runner.shakes, action: sendTapped)
        }
    }

    private var codeStep: some View {
        VStack(spacing: theme.spacing.xl) {
            AuthHeader(symbol: "envelope.badge", title: "Check your email",
                       subtitle: "Enter the \(codeLength)-digit code we sent to\n\(trimmedEmail)", accent: palette.accent, onAccent: palette.onAccent)
            KitoAuthCodeField(code: $code, length: codeLength, state: codeState, tint: tint) { checkCode($0) }
                .authShake(codeShakes, reduceMotion: reduceMotion)
                .overlay(alignment: .bottom) {
                    if isCheckingCode { ProgressView().tint(palette.accent).offset(y: 34) }
                }
                .onChange(of: code) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    if codeState == .error { codeState = .editing }
                    codeMessage = nil
                }
            InlineMessage(text: codeMessage, color: theme.colors.danger)
            if remaining > 0 {
                HStack(spacing: theme.spacing.sm) {
                    CountdownRing(fraction: Double(remaining) / Double(max(1, resendAfter)), color: palette.accent)
                        .frame(width: 20, height: 20)
                    Text(KitoCountdownFormat.resendTitle(remaining))
                        .font(theme.typography.label)
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.onBackground.opacity(0.6))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: remaining)
                }
                .accessibilityElement(children: .combine)
            } else {
                LinkButton(title: "Resend code", accent: palette.accent) { resend() }
            }
            LinkButton(title: "Use a different email", accent: theme.colors.onBackground.opacity(0.6)) {
                withAnimation(.authSpring(reduceMotion, bounce: 0.15)) { _ = flow.back() }
            }
        }
    }

    private var passwordStep: some View {
        VStack(spacing: theme.spacing.lg) {
            AuthHeader(symbol: "key.fill", title: "New password",
                       subtitle: "Make it strong. You’ll use it to sign in from now on.", accent: palette.accent, onAccent: palette.onAccent)
                .padding(.bottom, theme.spacing.sm)
            AuthTextField(title: "New password", symbol: "lock", text: $password, isSecure: true,
                          contentType: .newPassword, accent: palette.accent)
            KitoPasswordStrengthMeter(password: password, policy: policy)
                .padding(.horizontal, theme.spacing.xs)
            AuthTextField(title: "Confirm password", symbol: "lock.rotation", text: $confirmation, isSecure: true,
                          contentType: .newPassword, accent: palette.accent,
                          isInvalid: !confirmation.isEmpty && !password.hasPrefix(confirmation),
                          trailing: confirmation.isEmpty ? nil : AnyView(matchBadge))
            InlineMessage(text: runner.message, color: theme.colors.danger)
            MorphButton(title: "Reset password", phase: runner.phase, accent: palette.accent, onAccent: palette.onAccent,
                        isEnabled: evaluation.isAcceptable && passwordsMatch, shakes: runner.shakes, action: resetTapped)
                .padding(.top, theme.spacing.sm)
        }
    }

    private var matchBadge: some View {
        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(passwordsMatch ? theme.colors.success : theme.colors.danger.opacity(0.8))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: passwordsMatch)
            .accessibilityLabel(passwordsMatch ? "Passwords match" : "Passwords don’t match")
    }

    private var doneStep: some View {
        VStack(spacing: theme.spacing.xl) {
            SuccessBadge(color: theme.colors.success, size: 96, isShown: flow.current == .done)
                .padding(.top, theme.spacing.xxl)
            VStack(spacing: theme.spacing.sm) {
                Text("Password updated")
                    .font(theme.typography.displayMedium)
                    .foregroundStyle(theme.colors.onBackground)
                    .accessibilityAddTraits(.isHeader)
                Text("You can now sign in with your new password.")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.onBackground.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            MorphButton(title: "Back to sign in", phase: .idle, accent: palette.accent, onAccent: palette.onAccent) {
                finishHandler?()
            }
            .padding(.top, theme.spacing.lg)
        }
    }

    // MARK: Actions

    private func advance() {
        withAnimation(.authSpring(reduceMotion, bounce: 0.15)) { _ = flow.advance() }
        runner.reset()
    }

    private func sendTapped() {
        guard emailLooksValid else { return }
        let address = trimmedEmail
        Task { @MainActor in
            if await runner.run({ try await sendCode(address) }) {
                try? await Task.sleep(for: .seconds(0.6))
                code = ""
                codeState = .editing
                deadline = Date().addingTimeInterval(TimeInterval(resendAfter))
                advance()
            }
        }
    }

    private func resend() {
        let address = trimmedEmail
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching { try await sendCode(address) }
            switch outcome {
            case .success:
                AuthHaptics.success()
                deadline = Date().addingTimeInterval(TimeInterval(resendAfter))
            case .failure(let text):
                AuthHaptics.error()
                codeMessage = text
            case nil:
                break
            }
        }
    }

    private func checkCode(_ value: String) {
        guard !isCheckingCode else { return }
        isCheckingCode = true
        let address = trimmedEmail
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching { try await verifyCode(address, value) }
            isCheckingCode = false
            switch outcome {
            case .success:
                AuthHaptics.success()
                codeState = .success
                try? await Task.sleep(for: .seconds(0.7))
                advance()
            case .failure(let text):
                AuthHaptics.error()
                codeState = .error
                codeMessage = text
                codeShakes += 1
                try? await Task.sleep(for: .seconds(0.9))
                if codeState == .error {
                    code = ""
                    codeState = .editing
                }
            case nil:
                code = ""
            }
        }
    }

    private func resetTapped() {
        guard evaluation.isAcceptable, passwordsMatch else { return }
        let reset = KitoPasswordReset(email: trimmedEmail, code: code, newPassword: password)
        Task { @MainActor in
            if await runner.run({ try await resetPassword(reset) }) {
                try? await Task.sleep(for: .seconds(0.8))
                advance()
            }
        }
    }
}

public extension KitoForgotPasswordFlow {
    /// Called from "Back to sign in" on the last step.
    func onFinish(_ action: @escaping () -> Void) -> KitoForgotPasswordFlow {
        var copy = self
        copy.finishHandler = action
        return copy
    }

    /// Seconds before the code can be resent. Defaults to 30.
    func resendCooldown(_ seconds: Int) -> KitoForgotPasswordFlow {
        var copy = self
        copy.resendAfter = max(0, seconds)
        return copy
    }
}

/// Capsules for each step: done ones filled, the current one stretched.
struct StepIndicator: View {
    let count: Int
    let index: Int
    var accent: Color
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: theme.spacing.xs + 2) {
            ForEach(0..<count, id: \.self) { item in
                Capsule()
                    .fill(item <= index ? accent : theme.colors.border)
                    .frame(width: item == index ? 28 : 8, height: 8)
                    .shadow(color: item == index ? accent.opacity(0.3) : .clear, radius: 4, y: 2)
            }
        }
        .animation(.authSpring(reduceMotion, bounce: 0.4), value: index)
        .accessibilityHidden(true)
    }
}
