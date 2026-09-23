//
//  KitoMagicLinkScreen.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI

/// "Check your inbox" after sending a sign-in link: an animated envelope, an Open Mail button,
/// and a resend link behind a countdown.
///
/// ```swift
/// KitoMagicLinkScreen(email: "wycliff@example.com") {
///     try await api.sendMagicLink(to: email); return .success
/// }
/// .changeEmail { dismiss() }
/// ```
/// Handle the link itself with `.onOpenURL` in your app.
public struct KitoMagicLinkScreen: View {
    let email: String
    var tint: Color?
    let onResend: () async throws -> KitoAuthResult
    var resendAfter = 60
    var changeEmailHandler: (() -> Void)?
    var mailURL = URL(string: "message://")

    @Environment(\.kitoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deadline = Date()
    @State private var remaining = 0
    @State private var isResending = false
    @State private var sendCount = 0
    @State private var message: String?
    @State private var notice: String?

    public init(email: String, tint: Color? = nil, onResend: @escaping () async throws -> KitoAuthResult) {
        self.email = email
        self.tint = tint
        self.onResend = onResend
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }

    public var body: some View {
        ZStack {
            AuthBackground(accent: palette.accent)
            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    AnimatedEnvelope(accent: palette.accent, sendCount: sendCount)
                        .frame(width: 220, height: 210)
                        .padding(.top, theme.spacing.lg)

                    VStack(spacing: theme.spacing.sm) {
                        Text("Check your inbox")
                            .font(theme.typography.displayMedium)
                            .foregroundStyle(theme.colors.onBackground)
                            .accessibilityAddTraits(.isHeader)
                        Text("We sent a sign-in link to")
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.onBackground.opacity(0.62))
                        Text(email)
                            .font(theme.typography.bodyEmphasized)
                            .foregroundStyle(theme.colors.onBackground)
                            .padding(.horizontal, theme.spacing.md)
                            .padding(.vertical, theme.spacing.xs + 2)
                            .background(Capsule().fill(theme.colors.surfaceMuted))
                        Text("Tap the link in the email to sign in. It expires in 15 minutes.")
                            .font(theme.typography.label)
                            .foregroundStyle(theme.colors.onBackground.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top, theme.spacing.xs)
                    }

                    MorphButton(title: "Open Mail", systemImage: "envelope.open.fill", phase: .idle,
                                accent: palette.accent, onAccent: palette.onAccent) {
                        if let mailURL { openURL(mailURL) }
                    }
                    .padding(.top, theme.spacing.sm)

                    resendRow

                    InlineMessage(text: message, color: theme.colors.danger)
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(theme.typography.label)
                            .foregroundStyle(theme.colors.success)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let changeEmailHandler {
                        LinkButton(title: "Use a different email", accent: theme.colors.onBackground.opacity(0.6), action: changeEmailHandler)
                    }
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.bottom, theme.spacing.xxl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { deadline = Date().addingTimeInterval(TimeInterval(resendAfter)) }
        .task(id: deadline) {
            remaining = KitoCountdownFormat.secondsRemaining(until: deadline)
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining = KitoCountdownFormat.secondsRemaining(until: deadline)
            }
        }
        .animation(.spring(duration: 0.35), value: notice)
    }

    private var resendRow: some View {
        HStack(spacing: theme.spacing.sm) {
            Text("Didn’t get it?")
                .foregroundStyle(theme.colors.onBackground.opacity(0.55))
            if remaining > 0 {
                HStack(spacing: theme.spacing.xs + 2) {
                    CountdownRing(fraction: Double(remaining) / Double(max(1, resendAfter)), color: palette.accent, lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                    Text(KitoCountdownFormat.resendTitle(remaining))
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.onBackground.opacity(0.7))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: remaining)
                }
            } else {
                Button { resend() } label: {
                    HStack(spacing: theme.spacing.xs) {
                        if isResending { ProgressView().controlSize(.mini).tint(palette.accent) }
                        Text("Resend link").fontWeight(.semibold)
                    }
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(PressableStyle())
                .disabled(isResending)
            }
        }
        .font(theme.typography.label)
        .accessibilityElement(children: .combine)
    }

    private func resend() {
        guard !isResending else { return }
        isResending = true
        message = nil
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching(onResend)
            isResending = false
            switch outcome {
            case .success:
                AuthHaptics.success()
                sendCount += 1
                notice = "New link sent"
                deadline = Date().addingTimeInterval(TimeInterval(resendAfter))
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

public extension KitoMagicLinkScreen {
    /// Seconds before the link can be resent. Defaults to 60.
    func resendCooldown(_ seconds: Int) -> KitoMagicLinkScreen {
        var copy = self
        copy.resendAfter = max(0, seconds)
        return copy
    }

    /// Adds a "Use a different email" link.
    func changeEmail(_ action: @escaping () -> Void) -> KitoMagicLinkScreen {
        var copy = self
        copy.changeEmailHandler = action
        return copy
    }

    /// Where Open Mail goes. Defaults to the Mail app (`message://`); pass `googlegmail://` and
    /// so on for other clients, remembering `LSApplicationQueriesSchemes`.
    func mailApp(_ url: URL?) -> KitoMagicLinkScreen {
        var copy = self
        copy.mailURL = url
        return copy
    }
}

/// An envelope that bobs, opens its flap and slides the letter out, replaying on each resend.
struct AnimatedEnvelope: View {
    var accent: Color
    var sendCount: Int
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var bob = false

    var body: some View {
        let width: CGFloat = 150, height: CGFloat = 100
        ZStack {
            // Glow and sparkles
            Circle().fill(accent.opacity(0.07)).frame(width: 200, height: 200).scaleEffect(opened ? 1 : 0.7).offset(y: 14)
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: index.isMultiple(of: 2) ? 14 : 10, weight: .bold))
                    .foregroundStyle(accent.opacity(0.6))
                    .offset(sparkleOffset(index))
                    .scaleEffect(opened ? 1 : 0.1)
                    .opacity(opened ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.5).delay(0.6 + Double(index) * 0.07), value: opened)
            }

            ZStack(alignment: .top) {
                // Back of the envelope
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.85))
                    .frame(width: width, height: height)

                // The letter
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.colors.surface)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(accent.opacity(0.7)).frame(width: 44, height: 6)
                            Capsule().fill(theme.colors.border).frame(width: 90, height: 5)
                            Capsule().fill(theme.colors.border).frame(width: 70, height: 5)
                            Capsule().fill(accent).frame(width: 54, height: 14)
                                .overlay(Image(systemName: "link").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                        }
                        .padding(12)
                    }
                    .frame(width: width - 24, height: height - 10)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .offset(y: opened ? -58 : 6)
                    .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.35).delay(opened ? 0.35 : 0), value: opened)

                // Front pocket
                EnvelopePocket()
                    .fill(accent.gradient)
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: -1)

                // Flap, hinged on the top edge
                EnvelopeFlap()
                    .fill(accent)
                    .brightness(-0.06)
                    .frame(width: width, height: height * 0.58)
                    .rotation3DEffect(.degrees(opened ? 180 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
                    .zIndex(opened ? -1 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: opened)
            }
            .frame(width: width, height: height)
            .offset(y: (bob ? -6 : 6) + 34)
            .shadow(color: accent.opacity(0.3), radius: 18, y: 12)
        }
        .onAppear { play() }
        .onChange(of: sendCount) { _, _ in replay() }
        .accessibilityHidden(true)
    }

    private func sparkleOffset(_ index: Int) -> CGSize {
        let points: [CGSize] = [CGSize(width: -88, height: -46), CGSize(width: 84, height: -58), CGSize(width: -70, height: 48),
                                CGSize(width: 92, height: 26), CGSize(width: 10, height: -84)]
        return points[index % points.count]
    }

    private func play() {
        if reduceMotion {
            opened = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            opened = true
        }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { bob = true }
    }

    private func replay() {
        guard !reduceMotion else { return }
        opened = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            opened = true
        }
    }
}

/// The front of an envelope: a pocket with a V cut into its top.
struct EnvelopePocket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 12
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The triangular flap, pointing down when closed.
struct EnvelopeFlap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 10, y: rect.maxY - 6), control: CGPoint(x: rect.midX + 40, y: rect.maxY * 0.7))
        path.addQuadCurve(to: CGPoint(x: rect.midX - 10, y: rect.maxY - 6), control: CGPoint(x: rect.midX, y: rect.maxY + 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.minY), control: CGPoint(x: rect.midX - 40, y: rect.maxY * 0.7))
        path.closeSubpath()
        return path
    }
}
