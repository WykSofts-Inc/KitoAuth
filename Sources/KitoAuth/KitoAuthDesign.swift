//
//  KitoAuthDesign.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI
import UIKit

// MARK: - Colours

/// The accent for a screen: the caller's tint, or the theme's ink (black in light, white in dark).
struct AuthPalette {
    let theme: KitoTheme
    let tint: Color?

    var accent: Color { tint ?? theme.colors.onBackground }
    var onAccent: Color { tint == nil ? theme.colors.background : .white }
}

// MARK: - Motion

extension Animation {
    static func authSpring(_ reduceMotion: Bool, bounce: Double = 0.3) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: bounce)
    }
}

/// Horizontal shake driven by an ever-increasing trigger count.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}

extension View {
    /// Shakes each time `trigger` increments; still under Reduce Motion.
    func authShake(_ trigger: Int, reduceMotion: Bool) -> some View {
        modifier(ShakeEffect(travel: reduceMotion ? 0 : 9, animatableData: CGFloat(trigger)))
            .animation(reduceMotion ? nil : .linear(duration: 0.45), value: trigger)
    }
}

// MARK: - Haptics

@MainActor
enum AuthHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Checkmark

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.24))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.26))
        return path
    }
}

/// A circle that springs in and draws its tick, with a ring that ripples out.
struct SuccessBadge: View {
    var color: Color
    var size: CGFloat = 72
    var isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 3)
                .scaleEffect(isShown && !reduceMotion ? 1.6 : 1)
                .opacity(isShown && !reduceMotion ? 0 : (isShown ? 1 : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.8).delay(0.1), value: isShown)
            Circle()
                .fill(color.gradient)
                .shadow(color: color.opacity(0.4), radius: 14, y: 6)
                .scaleEffect(isShown ? 1 : 0.2)
                .opacity(isShown ? 1 : 0)
                .animation(.authSpring(reduceMotion, bounce: 0.45), value: isShown)
            CheckmarkShape()
                .trim(from: 0, to: isShown ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.5, height: size * 0.5)
                .animation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.35).delay(0.18), value: isShown)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(!isShown)
        .accessibilityLabel("Done")
    }
}

// MARK: - Header

/// Icon on a glowing badge, a title and a subtitle.
struct AuthHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var accent: Color
    var onAccent: Color = .white
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            ZStack {
                Circle().fill(accent.opacity(0.07)).frame(width: 100, height: 100)
                    .scaleEffect(appeared ? 1 : 0.6)
                Circle().fill(accent.gradient).frame(width: 68, height: 68)
                    .shadow(color: accent.opacity(0.35), radius: 14, y: 8)
                    .scaleEffect(appeared ? 1 : 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(onAccent)
                    .symbolEffect(.bounce, value: appeared)
                    .scaleEffect(appeared ? 1 : 0.4)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(theme.typography.displayMedium)
                .foregroundStyle(theme.colors.onBackground)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.onBackground.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { withAnimation(.authSpring(reduceMotion, bounce: 0.5)) { appeared = true } }
    }
}

// MARK: - Morphing button

enum MorphPhase: Equatable {
    case idle, loading, success, failure
    var isCollapsed: Bool { self == .loading || self == .success }
}

/// A black capsule that collapses into a spinner while working, turns into a green tick on
/// success and shakes red on failure.
struct MorphButton: View {
    let title: String
    var systemImage: String?
    var phase: MorphPhase
    var accent: Color
    var onAccent: Color
    var isEnabled = true
    var shakes = 0
    let action: () -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let height: CGFloat = 56

    private var fill: Color {
        switch phase {
        case .success: return theme.colors.success
        case .failure: return theme.colors.danger
        default: return accent
        }
    }

    var body: some View {
        GeometryReader { proxy in
            Button {
                guard phase == .idle || phase == .failure else { return }
                AuthHaptics.tap()
                action()
            } label: {
                ZStack {
                    Capsule().fill(fill.gradient)
                        .shadow(color: fill.opacity(isEnabled ? 0.28 : 0), radius: 12, y: 6)
                    switch phase {
                    case .idle, .failure:
                        HStack(spacing: theme.spacing.sm) {
                            if let systemImage { Image(systemName: systemImage) }
                            Text(title)
                        }
                        .font(theme.typography.button)
                        .foregroundStyle(phase == .failure ? .white : onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    case .loading:
                        ProgressView().tint(onAccent).transition(.opacity)
                    case .success:
                        CheckmarkShape()
                            .trim(from: 0, to: 1)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 24, height: 24)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .frame(width: phase.isCollapsed ? height : proxy.size.width, height: height)
                .frame(maxWidth: .infinity)
                .opacity(isEnabled || phase != .idle ? 1 : 0.35)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(!isEnabled)
            .animation(.authSpring(reduceMotion, bounce: 0.35), value: phase)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
        }
        .frame(height: height)
        .authShake(shakes, reduceMotion: reduceMotion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(phase == .loading ? "In progress" : phase == .success ? "Done" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled, phase == .idle || phase == .failure else { return }
            action()
        }
    }
}

/// Springs down a touch while pressed.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Runs an async server call behind a `MorphButton`: loading, then success or a shake.
@MainActor
@Observable
final class MorphRunner {
    var phase: MorphPhase = .idle
    var shakes = 0
    var message: String?

    /// Returns true on success. Cancellation resets quietly.
    func run(_ work: () async throws -> KitoAuthResult) async -> Bool {
        message = nil
        phase = .loading
        let outcome = await KitoAuthResult.catching(work)
        switch outcome {
        case .success:
            phase = .success
            AuthHaptics.success()
            return true
        case .failure(let text):
            fail(text)
            return false
        case nil:
            phase = .idle
            return false
        }
    }

    func fail(_ text: String?) {
        message = text
        phase = .failure
        shakes += 1
        AuthHaptics.error()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            if self.phase == .failure { self.phase = .idle }
        }
    }

    func reset() {
        phase = .idle
        message = nil
    }
}

// MARK: - Inline message

struct InlineMessage: View {
    let text: String?
    var color: Color
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        Group {
            if let text {
                Label(text, systemImage: "exclamationmark.circle.fill")
                    .font(theme.typography.label)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: text)
    }
}

// MARK: - Text field

/// A rounded field with an icon, an optional reveal toggle and an accent focus ring.
struct AuthTextField: View {
    let title: String
    let symbol: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var accent: Color
    var isInvalid = false
    var trailing: AnyView?

    @Environment(\.kitoTheme) private var theme
    @FocusState private var focused: Bool
    @State private var revealed = false

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(focused ? accent : theme.colors.onSurface.opacity(0.45))
                .frame(width: 22)
                .accessibilityHidden(true)
            Group {
                if isSecure && !revealed {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.onSurface)
            if let trailing { trailing }
            if isSecure {
                Button {
                    revealed.toggle()
                    AuthHaptics.tap()
                } label: {
                    Image(systemName: revealed ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, theme.spacing.lg)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).fill(theme.colors.surface))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                .stroke(isInvalid ? theme.colors.danger : (focused ? accent : theme.colors.border), lineWidth: focused || isInvalid ? 2 : 1)
        )
        .shadow(color: focused ? accent.opacity(0.12) : .clear, radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: focused)
        .animation(.easeInOut(duration: 0.2), value: isInvalid)
    }
}

// MARK: - Background

/// The page background with two soft accent glows.
struct AuthBackground: View {
    var accent: Color
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        ZStack {
            theme.colors.background
            Circle().fill(accent.opacity(0.07)).frame(width: 340).blur(radius: 70).offset(x: -140, y: -300)
            Circle().fill(theme.colors.primary.opacity(0.06)).frame(width: 300).blur(radius: 80).offset(x: 160, y: 320)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Small helpers

/// A plain accent text button with a press spring.
struct LinkButton: View {
    let title: String
    var accent: Color
    let action: () -> Void
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.typography.bodyEmphasized)
                .foregroundStyle(accent)
                .underline(false)
                .padding(.vertical, theme.spacing.xs)
        }
        .buttonStyle(PressableStyle())
    }
}

enum Pasteboard {
    @MainActor static func copy(_ string: String) {
        UIPasteboard.general.string = string
        AuthHaptics.success()
    }
}
