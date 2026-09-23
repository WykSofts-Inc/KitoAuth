//
//  KitoAppLock.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import KitoCore
import SwiftUI

/// How the app lock looks and behaves.
public struct KitoAppLockConfiguration: Sendable {
    public var title: String
    /// Shown as "Welcome back, <name>".
    public var userName: String?
    /// 4 to 8 digits.
    public var pinLength: Int
    /// Offer Face ID or Touch ID first when available.
    public var allowsBiometrics: Bool
    public var lockout: KitoLockoutPolicy
    /// Where wrong attempts are remembered so relaunching doesn't reset a lockout. Nil keeps them in memory.
    public var storageKey: String?
    /// Blur the app in the app switcher and whenever it isn't active.
    public var blursInAppSwitcher: Bool
    public var tint: Color?

    public init(title: String = "Enter passcode", userName: String? = nil, pinLength: Int = 4, allowsBiometrics: Bool = true,
                lockout: KitoLockoutPolicy = KitoLockoutPolicy(), storageKey: String? = "kito.appLock.lockout",
                blursInAppSwitcher: Bool = true, tint: Color? = nil) {
        self.title = title
        self.userName = userName
        self.pinLength = min(8, max(4, pinLength))
        self.allowsBiometrics = allowsBiometrics
        self.lockout = lockout
        self.storageKey = storageKey
        self.blursInAppSwitcher = blursInAppSwitcher
        self.tint = tint
    }
}

/// A lock screen: Face ID or Touch ID first, then a PIN pad with dots, a shake on a wrong PIN,
/// haptics, and a timed lockout after too many attempts.
///
/// ```swift
/// KitoAppLockScreen(configuration: .init(userName: "Wycliff N")) { pin in
///     keychain.pin == pin ? .success : .failure(message: "Wrong passcode")
/// } onUnlock: { isLocked = false }
/// ```
public struct KitoAppLockScreen: View {
    let configuration: KitoAppLockConfiguration
    let verifyPIN: (String) async throws -> KitoAuthResult
    let onUnlock: () -> Void
    var forgotHandler: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pin = ""
    @State private var lockout: KitoLockoutState
    @State private var status: Status = .entering
    @State private var shakes = 0
    @State private var message: String?
    @State private var now = Date()
    @State private var didPromptBiometrics = false

    enum Status: Equatable { case entering, checking, wrong, unlocked }

    public init(configuration: KitoAppLockConfiguration = KitoAppLockConfiguration(),
                verifyPIN: @escaping (String) async throws -> KitoAuthResult,
                onUnlock: @escaping () -> Void) {
        self.configuration = configuration
        self.verifyPIN = verifyPIN
        self.onUnlock = onUnlock
        _lockout = State(initialValue: LockoutStore.load(key: configuration.storageKey, policy: configuration.lockout))
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: configuration.tint) }
    private var isLockedOut: Bool { lockout.isLocked(at: now) }
    private var biometricsOffered: Bool { configuration.allowsBiometrics && KitoBiometricUnlock.isAvailable }

    public var body: some View {
        ZStack {
            AuthBackground(accent: palette.accent)
            VStack(spacing: theme.spacing.lg) {
                Spacer(minLength: theme.spacing.md)
                header
                dots
                    .authShake(shakes, reduceMotion: reduceMotion)
                statusLine
                    .frame(height: 20)
                Spacer(minLength: theme.spacing.sm)
                PinPad(accent: palette.accent,
                       biometricSymbol: biometricsOffered ? KitoBiometricUnlock.systemImage : nil,
                       canDelete: !pin.isEmpty,
                       isEnabled: !isLockedOut && status == .entering,
                       onDigit: enter, onDelete: deleteLast, onBiometrics: { Task { await tryBiometrics() } })
                    .opacity(isLockedOut ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isLockedOut)
                if let forgotHandler {
                    LinkButton(title: "Forgot passcode?", accent: theme.colors.onBackground.opacity(0.6), action: forgotHandler)
                }
                Spacer(minLength: theme.spacing.sm)
            }
            .padding(.horizontal, theme.spacing.lg)
            .frame(maxWidth: 420)
        }
        .task {
            guard !didPromptBiometrics else { return }
            didPromptBiometrics = true
            if biometricsOffered && !isLockedOut {
                try? await Task.sleep(for: .milliseconds(450))
                await tryBiometrics()
            }
        }
        .task(id: isLockedOut) {
            while lockout.isLocked(at: Date()) && !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .milliseconds(250))
            }
            now = Date()
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: theme.spacing.md) {
            ZStack {
                Circle().fill(palette.accent.opacity(status == .unlocked ? 0 : 0.1)).frame(width: 64, height: 64)
                Circle().fill(theme.colors.success.opacity(status == .unlocked ? 0.15 : 0)).frame(width: 64, height: 64)
                Image(systemName: status == .unlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(status == .unlocked ? theme.colors.success : palette.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: status == .unlocked)
            }
            .accessibilityHidden(true)
            Text(configuration.title)
                .font(theme.typography.titleLarge)
                .foregroundStyle(theme.colors.onBackground)
                .accessibilityAddTraits(.isHeader)
            if let name = configuration.userName {
                Text("Welcome back, \(name)")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.onBackground.opacity(0.6))
            }
        }
        .animation(.authSpring(reduceMotion), value: status)
    }

    private var dots: some View {
        HStack(spacing: theme.spacing.lg) {
            ForEach(0..<configuration.pinLength, id: \.self) { index in
                let filled = index < pin.count
                let color: Color = status == .wrong ? theme.colors.danger
                    : status == .unlocked ? theme.colors.success : palette.accent
                Circle()
                    .strokeBorder(filled || status != .entering ? color : theme.colors.border, lineWidth: 2)
                    .background(Circle().fill(filled || status == .unlocked ? color : .clear))
                    .frame(width: 16, height: 16)
                    .scaleEffect(filled && !reduceMotion && status == .entering ? 1.15 : 1)
                    .animation(.spring(duration: 0.3, bounce: 0.6), value: filled)
                    .animation(.authSpring(reduceMotion).delay(Double(index) * 0.03), value: status)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passcode")
        .accessibilityValue("\(pin.count) of \(configuration.pinLength) digits entered")
    }

    @ViewBuilder
    private var statusLine: some View {
        if isLockedOut {
            HStack(spacing: theme.spacing.xs + 2) {
                Image(systemName: "hourglass")
                Text("Try again in \(KitoCountdownFormat.clock(Int(lockout.remaining(at: now).rounded(.up))))")
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .font(theme.typography.label)
            .foregroundStyle(theme.colors.warning)
            .transition(.opacity)
        } else if let message {
            Text(message)
                .font(theme.typography.label)
                .foregroundStyle(theme.colors.danger)
                .transition(.opacity)
        }
    }

    // MARK: Actions

    private func enter(_ digit: Int) {
        guard status == .entering, !isLockedOut, pin.count < configuration.pinLength else { return }
        pin.append(String(digit))
        if pin.count == configuration.pinLength { check(pin) }
    }

    private func deleteLast() {
        guard status == .entering, !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func check(_ value: String) {
        status = .checking
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching { try await verifyPIN(value) }
            if outcome == .success {
                unlock()
                return
            }
            let startedLockout = lockout.recordFailure()
            LockoutStore.save(lockout, key: configuration.storageKey)
            now = Date()
            status = .wrong
            shakes += 1
            AuthHaptics.error()
            if startedLockout {
                message = nil
                UIAccessibility.post(notification: .announcement, argument: "Too many attempts. Try again later.")
            } else {
                let left = lockout.attemptsRemaining
                let reason: String? = { if case .failure(let text) = outcome { return text } else { return nil } }()
                message = left <= 2 ? "\(reason ?? "Wrong passcode") · \(left) \(left == 1 ? "attempt" : "attempts") left"
                                    : (reason ?? "Wrong passcode")
            }
            try? await Task.sleep(for: .seconds(0.6))
            pin = ""
            status = .entering
        }
    }

    private func unlock() {
        lockout.recordSuccess()
        LockoutStore.save(lockout, key: configuration.storageKey)
        message = nil
        pin = String(repeating: "•", count: configuration.pinLength)
        status = .unlocked
        AuthHaptics.success()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.55))
            onUnlock()
        }
    }

    private func tryBiometrics() async {
        guard biometricsOffered, !isLockedOut, status == .entering else { return }
        do {
            if try await KitoBiometricUnlock.authenticate(reason: "Unlock \(appName)") { unlock() }
        } catch {
            // Cancelled or unavailable: the PIN pad stays.
        }
    }

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "the app"
    }
}

public extension KitoAppLockScreen {
    /// Adds a "Forgot passcode?" link under the keypad.
    func forgotPasscode(_ action: @escaping () -> Void) -> KitoAppLockScreen {
        var copy = self
        copy.forgotHandler = action
        return copy
    }
}

// MARK: - Keypad

struct PinPad: View {
    var accent: Color
    var biometricSymbol: String?
    var canDelete: Bool
    var isEnabled: Bool
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let onBiometrics: () -> Void

    @Environment(\.kitoTheme) private var theme
    private var columnSpacing: CGFloat { theme.spacing.xl - 4 }
    private let letters = ["", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"]

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: columnSpacing) {
                    ForEach(1...3, id: \.self) { column in
                        let digit = row * 3 + column
                        PinKey(accent: accent) { onDigit(digit) } label: {
                            VStack(spacing: 0) {
                                Text("\(digit)").font(.system(size: 30, weight: .regular, design: .rounded))
                                Text(letters[digit - 1]).font(.system(size: 9, weight: .bold)).tracking(1.5).opacity(0.5)
                                    .frame(height: 10)
                            }
                        }
                        .accessibilityLabel("\(digit)")
                    }
                }
            }
            HStack(spacing: columnSpacing) {
                if let biometricSymbol {
                    PinKey(accent: accent, isPlain: true, action: onBiometrics) {
                        Image(systemName: biometricSymbol).font(.system(size: 28, weight: .regular))
                    }
                    .accessibilityLabel(KitoBiometricUnlock.name ?? "Biometrics")
                } else {
                    Color.clear.frame(width: PinKeyStyle.size, height: PinKeyStyle.size)
                }
                PinKey(accent: accent) { onDigit(0) } label: {
                    Text("0").font(.system(size: 30, weight: .regular, design: .rounded))
                }
                .accessibilityLabel("0")
                PinKey(accent: accent, isPlain: true, action: onDelete) {
                    Image(systemName: "delete.backward").font(.system(size: 22, weight: .medium))
                }
                .opacity(canDelete ? 1 : 0)
                .disabled(!canDelete)
                .accessibilityLabel("Delete")
            }
        }
        .foregroundStyle(theme.colors.onBackground)
        .disabled(!isEnabled)
    }
}

/// A round key that flashes the accent when pressed.
struct PinKey<Label: View>: View {
    var accent: Color
    var isPlain = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            AuthHaptics.tap()
            action()
        } label: {
            label()
        }
        .buttonStyle(PinKeyStyle(accent: accent, isPlain: isPlain))
    }
}

struct PinKeyStyle: ButtonStyle {
    static let size: CGFloat = 72
    var accent: Color
    var isPlain: Bool
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Self.size, height: Self.size)
            .background {
                if !isPlain {
                    Circle()
                        .fill(configuration.isPressed ? accent.opacity(0.18) : theme.colors.surface)
                        .overlay(Circle().stroke(theme.colors.border.opacity(0.7), lineWidth: 1))
                        .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.05), radius: 6, y: 3)
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Persistence

enum LockoutStore {
    static func load(key: String?, policy: KitoLockoutPolicy) -> KitoLockoutState {
        guard let key, let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(KitoLockoutState.self, from: data), saved.policy == policy else {
            return KitoLockoutState(policy: policy)
        }
        return saved
    }

    static func save(_ state: KitoLockoutState, key: String?) {
        guard let key, let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Modifier

public extension View {
    /// Covers the app with `KitoAppLockScreen` while `isLocked` is true, locks it again after it
    /// has been in the background for `timeout` seconds (0 locks immediately), and blurs it in
    /// the app switcher. Apply it to your root view.
    ///
    /// ```swift
    /// ContentView()
    ///     .kitoAppLock(isLocked: $isLocked, timeout: 30) { pin in
    ///         pin == storedPIN ? .success : .failure(message: "Wrong passcode")
    ///     }
    /// ```
    func kitoAppLock(isLocked: Binding<Bool>, timeout: TimeInterval = 0,
                     configuration: KitoAppLockConfiguration = KitoAppLockConfiguration(),
                     verifyPIN: @escaping (String) async throws -> KitoAuthResult) -> some View {
        modifier(AppLockModifier(isLocked: isLocked, timeout: timeout, configuration: configuration, verifyPIN: verifyPIN))
    }
}

struct AppLockModifier: ViewModifier {
    @Binding var isLocked: Bool
    let timeout: TimeInterval
    let configuration: KitoAppLockConfiguration
    let verifyPIN: (String) async throws -> KitoAuthResult

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backgroundedAt: Date?

    private var obscured: Bool { configuration.blursInAppSwitcher && scenePhase != .active && !isLocked }

    func body(content: Content) -> some View {
        content
            .blur(radius: obscured || isLocked ? 20 : 0)
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)
            .overlay {
                if obscured {
                    PrivacyCover(accent: configuration.tint)
                        .transition(.opacity)
                }
            }
            .overlay {
                if isLocked {
                    KitoAppLockScreen(configuration: configuration, verifyPIN: verifyPIN) {
                        withAnimation(.authSpring(reduceMotion, bounce: 0.2)) { isLocked = false }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: obscured)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    backgroundedAt = backgroundedAt ?? Date()
                    if timeout <= 0 { isLocked = true }
                case .active:
                    if let since = backgroundedAt, Date().timeIntervalSince(since) >= timeout { isLocked = true }
                    backgroundedAt = nil
                default:
                    break
                }
            }
    }
}

/// Shown over the blurred app while it's inactive, so the app switcher never shows content.
struct PrivacyCover: View {
    var accent: Color?
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accent ?? theme.colors.onBackground)
                .padding(26)
                .background(Circle().fill(theme.colors.surface.opacity(0.8)))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
