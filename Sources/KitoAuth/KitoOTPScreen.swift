//
//  KitoOTPScreen.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI

/// Where a one-time code is sent.
public enum KitoOTPChannel: String, CaseIterable, Identifiable, Sendable {
    case sms, email, whatsApp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sms: return "SMS"
        case .email: return "Email"
        case .whatsApp: return "WhatsApp"
        }
    }

    public var systemImage: String {
        switch self {
        case .sms: return "message.fill"
        case .email: return "envelope.fill"
        case .whatsApp: return "phone.bubble.fill"
        }
    }

    /// "by SMS", "by email", "on WhatsApp".
    var phrase: String {
        switch self {
        case .sms: return "by SMS"
        case .email: return "by email"
        case .whatsApp: return "on WhatsApp"
        }
    }
}

/// Enter a one-time code: animated digit boxes with paste and SMS autofill, auto-submit,
/// a resend countdown ring, channel chips, a shake on a wrong code and a success morph.
///
/// ```swift
/// KitoOTPScreen(destination: "+254 712 345 678") { code in
///     try await api.verify(code) ? .success : .failure(message: "That code isn’t right")
/// }
/// .channels([.sms, .whatsApp])
/// .resend(after: 30) { channel in try await api.sendCode(via: channel); return .success }
/// .changeDestination { dismiss() }
/// .onVerified { router.push(.home) }
/// ```
public struct KitoOTPScreen: View {
    let destination: String
    let length: Int
    var tint: Color?
    let onVerify: (String) async throws -> KitoAuthResult
    var channelOptions: [KitoOTPChannel] = [.sms]
    var initialChannel: KitoOTPChannel?
    var resendAfter = 30
    var resendHandler: ((KitoOTPChannel) async throws -> KitoAuthResult)?
    var changeDestinationHandler: (() -> Void)?
    var verifiedHandler: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var code = ""
    @State private var fieldState: KitoCodeFieldState = .editing
    @State private var shakes = 0
    @State private var isVerifying = false
    @State private var message: String?
    @State private var channel: KitoOTPChannel?
    @State private var deadline = Date()
    @State private var remaining = 0
    @State private var isResending = false
    @State private var notice: String?

    /// - Parameters:
    ///   - destination: The phone number or email shown in the subtitle.
    ///   - length: 4 to 8 digits.
    ///   - onVerify: Called once all digits are in. Return `.failure(message:)` for a wrong code.
    public init(destination: String, length: Int = 6, tint: Color? = nil,
                onVerify: @escaping (String) async throws -> KitoAuthResult) {
        self.destination = destination
        self.length = min(8, max(4, length))
        self.tint = tint
        self.onVerify = onVerify
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var activeChannel: KitoOTPChannel { channel ?? initialChannel ?? channelOptions.first ?? .sms }
    private var isEmail: Bool { destination.contains("@") }

    public var body: some View {
        ZStack {
            AuthBackground(accent: palette.accent)
            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    AuthHeader(symbol: activeChannel.systemImage, title: fieldState == .success ? "You’re verified" : "Enter the code",
                               subtitle: "We sent a \(length)-digit code \(activeChannel.phrase) to\n\(destination)",
                               accent: fieldState == .success ? theme.colors.success : palette.accent,
                               onAccent: fieldState == .success ? .white : palette.onAccent)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: activeChannel)

                    if let changeDestinationHandler {
                        LinkButton(title: isEmail ? "Change email" : "Change number", accent: palette.accent, action: changeDestinationHandler)
                            .padding(.top, -theme.spacing.md)
                    }

                    if channelOptions.count > 1 && fieldState != .success {
                        chips
                    }

                    ZStack {
                        KitoAuthCodeField(code: $code, length: length, state: fieldState, tint: tint) { submit($0) }
                            .authShake(shakes, reduceMotion: reduceMotion)
                            .scaleEffect(fieldState == .success && !reduceMotion ? 0.4 : 1)
                            .opacity(fieldState == .success ? 0 : 1)
                            .blur(radius: fieldState == .success && !reduceMotion ? 6 : 0)
                        SuccessBadge(color: theme.colors.success, size: 76, isShown: fieldState == .success)
                    }
                    .animation(.authSpring(reduceMotion, bounce: 0.3).delay(fieldState == .success ? 0.25 : 0), value: fieldState)
                    .overlay(alignment: .bottom) {
                        if isVerifying {
                            ProgressView().tint(palette.accent).offset(y: 36).transition(.opacity)
                        }
                    }

                    InlineMessage(text: message, color: theme.colors.danger)

                    if fieldState != .success, resendHandler != nil {
                        resendRow
                    }

                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(theme.typography.label)
                            .foregroundStyle(theme.colors.success)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.vertical, theme.spacing.xxl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.never)
        }
        .onChange(of: code) { _, newValue in
            guard !newValue.isEmpty else { return }
            if fieldState == .error { fieldState = .editing }
            message = nil
        }
        .onAppear { restartCountdown() }
        .task(id: deadline) {
            remaining = KitoCountdownFormat.secondsRemaining(until: deadline)
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining = KitoCountdownFormat.secondsRemaining(until: deadline)
            }
        }
        .animation(.spring(duration: 0.35), value: notice)
    }

    // MARK: Pieces

    private var chips: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(channelOptions) { item in
                let selected = item == activeChannel
                Button {
                    guard item != activeChannel else { return }
                    AuthHaptics.tap()
                    withAnimation(.authSpring(reduceMotion)) { channel = item }
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .font(theme.typography.label)
                        .padding(.horizontal, theme.spacing.md)
                        .padding(.vertical, theme.spacing.sm)
                        .foregroundStyle(selected ? palette.onAccent : theme.colors.onSurface)
                        .background(Capsule().fill(selected ? palette.accent : theme.colors.surface))
                        .overlay(Capsule().stroke(selected ? .clear : theme.colors.border, lineWidth: 1))
                        .shadow(color: selected ? palette.accent.opacity(0.2) : .clear, radius: 8, y: 4)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint("Send the code \(item.phrase)")
            }
        }
    }

    private var resendRow: some View {
        Group {
            if remaining > 0 {
                HStack(spacing: theme.spacing.sm) {
                    CountdownRing(fraction: Double(remaining) / Double(max(1, resendAfter)), color: palette.accent)
                        .frame(width: 22, height: 22)
                    Text(KitoCountdownFormat.resendTitle(remaining))
                        .font(theme.typography.label)
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.onBackground.opacity(0.6))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: remaining)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button { resendCode() } label: {
                    HStack(spacing: theme.spacing.sm) {
                        if isResending {
                            ProgressView().controlSize(.small).tint(palette.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(activeChannel == .sms ? "Resend code" : "Send \(activeChannel.phrase)")
                    }
                    .font(theme.typography.bodyEmphasized)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.sm + 2)
                    .background(Capsule().fill(palette.accent.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
                .disabled(isResending)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.authSpring(reduceMotion), value: remaining > 0)
    }

    // MARK: Actions

    private func restartCountdown() {
        deadline = Date().addingTimeInterval(TimeInterval(max(0, resendAfter)))
    }

    private func submit(_ value: String) {
        guard !isVerifying, fieldState != .success else { return }
        isVerifying = true
        message = nil
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching { try await onVerify(value) }
            isVerifying = false
            switch outcome {
            case .success:
                AuthHaptics.success()
                fieldState = .success
                try? await Task.sleep(for: .seconds(1.1))
                verifiedHandler?()
            case .failure(let text):
                AuthHaptics.error()
                fieldState = .error
                message = text
                shakes += 1
                try? await Task.sleep(for: .seconds(0.9))
                if fieldState == .error {
                    code = ""
                    fieldState = .editing
                }
            case nil:
                code = ""
            }
        }
    }

    private func resendCode() {
        guard let resendHandler, !isResending else { return }
        isResending = true
        let via = activeChannel
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching { try await resendHandler(via) }
            isResending = false
            switch outcome {
            case .success:
                AuthHaptics.success()
                code = ""
                fieldState = .editing
                message = nil
                notice = "New code sent \(via.phrase)"
                restartCountdown()
                try? await Task.sleep(for: .seconds(2.5))
                notice = nil
            case .failure(let text):
                AuthHaptics.error()
                message = text
            case nil:
                break
            }
        }
    }
}

public extension KitoOTPScreen {
    /// Shows a chip for each channel so people can switch between SMS, email and WhatsApp.
    func channels(_ channels: [KitoOTPChannel], selected: KitoOTPChannel? = nil) -> KitoOTPScreen {
        var copy = self
        copy.channelOptions = channels.isEmpty ? [.sms] : channels
        copy.initialChannel = selected
        return copy
    }

    /// Adds the resend countdown ring and button. `send` receives the selected channel.
    func resend(after seconds: Int = 30, send: @escaping (KitoOTPChannel) async throws -> KitoAuthResult) -> KitoOTPScreen {
        var copy = self
        copy.resendAfter = seconds
        copy.resendHandler = send
        return copy
    }

    /// Adds a "Change number" (or "Change email") link under the subtitle.
    func changeDestination(_ action: @escaping () -> Void) -> KitoOTPScreen {
        var copy = self
        copy.changeDestinationHandler = action
        return copy
    }

    /// Called after the success animation finishes.
    func onVerified(_ action: @escaping () -> Void) -> KitoOTPScreen {
        var copy = self
        copy.verifiedHandler = action
        return copy
    }
}

/// A ring that empties clockwise as a countdown runs.
struct CountdownRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 3
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        ZStack {
            Circle().stroke(theme.colors.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
        }
        .accessibilityHidden(true)
    }
}
