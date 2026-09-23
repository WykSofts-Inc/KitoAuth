//
//  KitoTwoFactorSetup.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import KitoCore
import SwiftUI
import UIKit

/// QR codes from Core Image.
public enum KitoQRCode {
    /// CPU rendering: a QR is tiny, and it skips the GPU warm-up that can take seconds on first use.
    private static let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    /// A crisp black-on-white QR code for `string`, `scale` pixels per module.
    public static func image(for string: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// The steps of `KitoTwoFactorSetup`, in order.
public enum KitoTwoFactorStep: Hashable, CaseIterable, Sendable {
    case scan, verify, recoveryCodes
}

/// Turn on two-factor sign-in with an authenticator app: a QR code (with the key in readable
/// groups and a copy button for manual entry), a code check, then recovery codes to copy or share.
///
/// ```swift
/// KitoTwoFactorSetup(issuer: "Kito", account: "wycliff@example.com", secret: server.secret,
///                    recoveryCodes: server.recoveryCodes) { code in
///     try await api.confirmTwoFactor(code) ? .success : .failure(message: "That code didn’t match")
/// }
/// .onFinish { dismiss() }
/// ```
/// Leave `onVerify` out to check codes on the device with `KitoTOTP`, handy for demos.
public struct KitoTwoFactorSetup: View {
    let issuer: String
    let account: String
    var tint: Color?
    let onVerify: ((String) async throws -> KitoAuthResult)?
    var finishHandler: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var secret: String
    @State private var recoveryCodes: [String]
    @State private var flow = KitoStepFlow<KitoTwoFactorStep>()
    @State private var qrImage: UIImage?
    @State private var code = ""
    @State private var codeState: KitoCodeFieldState = .editing
    @State private var shakes = 0
    @State private var message: String?
    @State private var isChecking = false
    @State private var copiedKey = false
    @State private var copiedCodes = false
    @State private var savedCodes = false

    /// - Parameters:
    ///   - secret: Base32. Generate it on your server; the default is a random one for demos.
    ///   - recoveryCodes: From your server; the default generates ten.
    ///   - onVerify: Confirms the first code with your server. Nil checks it locally.
    public init(issuer: String, account: String, secret: String = KitoBase32.randomSecret(),
                recoveryCodes: [String] = KitoRecoveryCodes.generate(), tint: Color? = nil,
                onVerify: ((String) async throws -> KitoAuthResult)? = nil) {
        self.issuer = issuer
        self.account = account
        self.tint = tint
        self.onVerify = onVerify
        _secret = State(initialValue: secret)
        _recoveryCodes = State(initialValue: recoveryCodes)
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var otpauth: KitoOTPAuthURL { KitoOTPAuthURL(issuer: issuer, account: account, secret: secret) }

    public var body: some View {
        ZStack {
            AuthBackground(accent: palette.accent)
            VStack(spacing: 0) {
                HStack {
                    Button {
                        AuthHaptics.tap()
                        withAnimation(.authSpring(reduceMotion, bounce: 0.15)) { _ = flow.back() }
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
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, theme.spacing.lg)
                .padding(.top, theme.spacing.md)

                ScrollView {
                    ZStack {
                        switch flow.current {
                        case .scan: scanStep.transition(transition)
                        case .verify: verifyStep.transition(transition)
                        case .recoveryCodes: recoveryStep.transition(transition)
                        }
                    }
                    .padding(.horizontal, theme.spacing.xl)
                    .padding(.vertical, theme.spacing.xl)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: otpauth.string) {
            let string = otpauth.string
            qrImage = await Task.detached(priority: .userInitiated) { KitoQRCode.image(for: string) }.value
        }
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let forward = flow.direction == .forward
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: Scan

    private var scanStep: some View {
        VStack(spacing: theme.spacing.xl) {
            AuthHeader(symbol: "qrcode.viewfinder", title: "Scan with your authenticator",
                       subtitle: "Open Google Authenticator, 1Password or Passwords and scan this code.", accent: palette.accent, onAccent: palette.onAccent)
            QRCard(image: qrImage, accent: palette.accent)
                .accessibilityLabel("QR code for \(issuer), \(account)")

            VStack(spacing: theme.spacing.md) {
                Text("Can’t scan? Enter this key")
                    .font(theme.typography.label)
                    .foregroundStyle(theme.colors.onBackground.opacity(0.55))
                SecretGroups(groups: KitoBase32.group(secret), copied: copiedKey, accent: palette.accent) {
                    Pasteboard.copy(KitoBase32.normalized(secret))
                    flash($copiedKey)
                }
            }

            if let url = otpauth.url {
                LinkButton(title: "Open in authenticator app", accent: palette.accent) { openURL(url) }
            }

            MorphButton(title: "Next", systemImage: "arrow.right", phase: .idle, accent: palette.accent, onAccent: palette.onAccent) {
                withAnimation(.authSpring(reduceMotion, bounce: 0.15)) { _ = flow.advance() }
            }
        }
    }

    // MARK: Verify

    private var verifyStep: some View {
        VStack(spacing: theme.spacing.xl) {
            AuthHeader(symbol: "lock.shield", title: "Enter the code",
                       subtitle: "Type the 6-digit code \(issuer) shows in your authenticator app.", accent: palette.accent, onAccent: palette.onAccent)
            KitoCodeField(code: $code, length: 6, state: codeState, tint: tint) { check($0) }
                .authShake(shakes, reduceMotion: reduceMotion)
                .overlay(alignment: .bottom) {
                    if isChecking { ProgressView().tint(palette.accent).offset(y: 34) }
                }
                .onChange(of: code) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    if codeState == .error { codeState = .editing }
                    message = nil
                }
            InlineMessage(text: message, color: theme.colors.danger)
        }
    }

    private func check(_ value: String) {
        guard !isChecking else { return }
        isChecking = true
        let secret = secret
        Task { @MainActor in
            let outcome = await KitoAuthResult.catching {
                if let onVerify { return try await onVerify(value) }
                return KitoTOTP.isValid(value, secret: secret) ? .success : .failure(message: "That code didn’t match. Try the newest one.")
            }
            isChecking = false
            switch outcome {
            case .success:
                AuthHaptics.success()
                codeState = .success
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.authSpring(reduceMotion, bounce: 0.15)) { _ = flow.advance() }
            case .failure(let text):
                AuthHaptics.error()
                codeState = .error
                message = text
                shakes += 1
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

    // MARK: Recovery codes

    private var recoveryStep: some View {
        VStack(spacing: theme.spacing.lg) {
            AuthHeader(symbol: "key.horizontal.fill", title: "Save your recovery codes",
                       subtitle: "Each one signs you in once if you lose your phone. Keep them somewhere safe.",
                       accent: theme.colors.success)
            KitoRecoveryCodesView(codes: recoveryCodes, tint: tint)
            Button {
                AuthHaptics.tap()
                savedCodes.toggle()
            } label: {
                HStack(spacing: theme.spacing.sm) {
                    Image(systemName: savedCodes ? "checkmark.square.fill" : "square")
                        .foregroundStyle(savedCodes ? palette.accent : theme.colors.onBackground.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                    Text("I’ve saved these codes")
                        .foregroundStyle(theme.colors.onBackground)
                }
                .font(theme.typography.bodyEmphasized)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(savedCodes ? .isSelected : [])
            MorphButton(title: "Finish", phase: .idle, accent: palette.accent, onAccent: palette.onAccent, isEnabled: savedCodes) {
                finishHandler?()
            }
        }
    }

    private func flash(_ binding: Binding<Bool>) {
        binding.wrappedValue = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            binding.wrappedValue = false
        }
    }
}

public extension KitoTwoFactorSetup {
    /// Called from Finish on the recovery codes step.
    func onFinish(_ action: @escaping () -> Void) -> KitoTwoFactorSetup {
        var copy = self
        copy.finishHandler = action
        return copy
    }
}

/// A numbered two-column grid of recovery codes with Copy all and Share.
public struct KitoRecoveryCodesView: View {
    let codes: [String]
    var tint: Color?

    @Environment(\.kitoTheme) private var theme
    @State private var copied = false

    public init(codes: [String], tint: Color? = nil) {
        self.codes = codes
        self.tint = tint
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var shareText: String { codes.joined(separator: "\n") }

    public var body: some View {
        VStack(spacing: theme.spacing.md) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: theme.spacing.sm) {
                ForEach(Array(codes.enumerated()), id: \.offset) { index, code in
                    HStack(spacing: theme.spacing.sm) {
                        Text("\(index + 1)")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.onSurface.opacity(0.4))
                            .frame(width: 16, alignment: .trailing)
                        Text(code)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.colors.onSurface)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, theme.spacing.sm)
                    .padding(.horizontal, theme.spacing.md)
                    .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(theme.colors.surfaceMuted))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Code \(index + 1): \(code.map(String.init).joined(separator: " "))")
                }
            }
            HStack(spacing: theme.spacing.sm) {
                Button {
                    Pasteboard.copy(shareText)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy all", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleStyle(accent: copied ? theme.colors.success : palette.accent))
                ShareLink(item: shareText, subject: Text("Recovery codes")) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleStyle(accent: palette.accent))
            }
            .animation(.spring(duration: 0.3), value: copied)
        }
        .padding(theme.spacing.lg)
        .background(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).fill(theme.colors.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).stroke(theme.colors.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

/// A tinted capsule for secondary actions.
struct SecondaryCapsuleStyle: ButtonStyle {
    var accent: Color
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.label)
            .foregroundStyle(accent)
            .padding(.vertical, theme.spacing.md)
            .background(Capsule().fill(accent.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// The QR on a white card with scanner corners and a sweeping line.
struct QRCard: View {
    let image: UIImage?
    var accent: Color
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            Group {
                if let image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    ProgressView()
                }
            }
            .padding(22)
            .overlay {
                if !reduceMotion && image != nil {
                    GeometryReader { proxy in
                        LinearGradient(colors: [accent.opacity(0), accent.opacity(0.16), accent.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                            .offset(y: sweep ? proxy.size.height - 20 : -20)
                            .blendMode(.multiply)
                    }
                    .padding(22)
                    .allowsHitTesting(false)
                }
            }
            ScannerCorners().stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(8)
                .scaleEffect(appeared ? 1 : 1.15)
                .opacity(appeared ? 1 : 0)
        }
        .frame(width: 230, height: 230)
        .animation(.easeOut(duration: 0.3), value: image != nil)
        .onAppear {
            withAnimation(.authSpring(reduceMotion, bounce: 0.4).delay(0.2)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

/// Four L-shaped corners.
struct ScannerCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.14
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (point, dx, dy) in corners {
            path.move(to: CGPoint(x: point.x, y: point.y + dy * length))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x + dx * length, y: point.y))
        }
        return path
    }
}

/// The secret in monospaced groups with a copy button that turns into a tick.
struct SecretGroups: View {
    let groups: [String]
    var copied: Bool
    var accent: Color
    let onCopy: () -> Void
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            FlowRows(items: groups, perRow: 4) { group in
                Text(group)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.colors.onSurface)
                    .padding(.horizontal, theme.spacing.sm)
                    .padding(.vertical, theme.spacing.xs + 2)
                    .background(RoundedRectangle(cornerRadius: theme.radii.sm, style: .continuous).fill(theme.colors.surfaceMuted))
            }
            .textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup key")
            .accessibilityValue(groups.joined(separator: " ").map(String.init).joined(separator: " "))

            Button(action: onCopy) {
                Label(copied ? "Copied" : "Copy key", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, theme.spacing.xl)
            }
            .buttonStyle(SecondaryCapsuleStyle(accent: copied ? theme.colors.success : accent))
            .animation(.spring(duration: 0.3), value: copied)
        }
    }
}

/// Lays items out in rows of `perRow`, centred.
struct FlowRows<Content: View>: View {
    let items: [String]
    let perRow: Int
    @ViewBuilder let content: (String) -> Content
    @Environment(\.kitoTheme) private var theme

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: max(1, perRow)).map { Array(items[$0 ..< min($0 + perRow, items.count)]) }
        VStack(spacing: theme.spacing.xs + 2) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: theme.spacing.xs + 2) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        content(rows[row][column])
                    }
                }
            }
        }
    }
}
