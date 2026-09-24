//
//  KitoAppleSignIn.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import AuthenticationServices
import KitoCore
import SwiftUI

/// What Sign in with Apple returns. Apple only shares `email` and `name` the first time a person
/// signs in to your app, so store them then; later sign-ins carry only `userID` and the token.
public struct KitoAppleCredential: Equatable, Sendable {
    /// Stable per person and team. Use it as the account key.
    public let userID: String
    public let email: String?
    public let name: PersonNameComponents?
    /// A JWT to send to your server for verification.
    public let identityToken: String?
    /// A short-lived code your server can exchange with Apple.
    public let authorizationCode: String?
    /// True when Apple thinks this is a real person.
    public let isLikelyReal: Bool

    public init(userID: String, email: String? = nil, name: PersonNameComponents? = nil, identityToken: String? = nil,
                authorizationCode: String? = nil, isLikelyReal: Bool = true) {
        self.userID = userID
        self.email = email
        self.name = name
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.isLikelyReal = isLikelyReal
    }

    /// "Wycliff Njenga", or nil when Apple didn't share a name.
    public var displayName: String? {
        guard let name else { return nil }
        let text = PersonNameComponentsFormatter().string(from: name)
        return text.isEmpty ? nil : text
    }
}

/// Sign in with Apple, as one async call.
///
/// ```swift
/// let credential = try await KitoAppleSignIn.signIn()
/// ```
/// Needs the Sign in with Apple capability. Throws `KitoAuthError.cancelled` when the person
/// closes the sheet.
public enum KitoAppleSignIn {
    @MainActor
    public static func signIn(scopes: [ASAuthorization.Scope] = [.fullName, .email], nonce: String? = nil) async throws -> KitoAppleCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = scopes
        if let nonce { request.nonce = nonce }
        do {
            let authorization = try await AuthorizationSession.perform([request])
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw KitoAuthError.failed(message: "Apple returned an unexpected credential.")
            }
            return KitoAppleCredential(
                userID: credential.user,
                email: credential.email,
                name: credential.fullName.flatMap { $0.givenName == nil && $0.familyName == nil ? nil : $0 },
                identityToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) },
                authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                isLikelyReal: credential.realUserStatus != .unsupported
            )
        } catch {
            throw AuthorizationSession.map(error)
        }
    }

    /// Whether Apple still considers `userID` signed in. Check at launch and sign out on `.revoked`.
    public static func credentialState(for userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }
}

/// The look of `KitoAppleSignInButton`.
public enum KitoAppleButtonStyle: Sendable {
    /// Black capsule, white text. Best on light backgrounds.
    case black
    /// White capsule, black text. Best on dark or photo backgrounds.
    case white
    /// Transparent with an outline that follows the text colour.
    case outline
}

/// The wording on `KitoAppleSignInButton`, from Apple's approved set.
public enum KitoAppleButtonLabel: Sendable {
    case signIn, `continue`, signUp

    var title: String {
        switch self {
        case .signIn: return "Sign in with Apple"
        case .continue: return "Continue with Apple"
        case .signUp: return "Sign up with Apple"
        }
    }
}

/// A Kito capsule Sign in with Apple button. It runs the Apple sheet, then hands you the
/// credential to check with your server, morphing into a spinner and a tick on success.
///
/// ```swift
/// KitoAppleSignInButton(.black) { credential in
///     try await api.signIn(appleToken: credential.identityToken)
///     return .success
/// }
/// ```
public struct KitoAppleSignInButton: View {
    let style: KitoAppleButtonStyle
    let label: KitoAppleButtonLabel
    var scopes: [ASAuthorization.Scope]
    var tint: Color?
    let onCredential: (KitoAppleCredential) async throws -> KitoAuthResult
    var onError: ((KitoAuthError) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runner = MorphRunner()

    /// - Parameters:
    ///   - style: `.black`, `.white` or `.outline`.
    ///   - onCredential: Verify with your server and return `.success` or `.failure(message:)`.
    ///   - onError: Called for errors other than cancellation (which resets quietly).
    public init(_ style: KitoAppleButtonStyle = .black, label: KitoAppleButtonLabel = .continue,
                scopes: [ASAuthorization.Scope] = [.fullName, .email], tint: Color? = nil,
                onCredential: @escaping (KitoAppleCredential) async throws -> KitoAuthResult,
                onError: ((KitoAuthError) -> Void)? = nil) {
        self.style = style
        self.label = label
        self.scopes = scopes
        self.tint = tint
        self.onCredential = onCredential
        self.onError = onError
    }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            ProviderCapsule(title: label.title, style: capsuleStyle, phase: runner.phase, shakes: runner.shakes) {
                AppleLogo()
            } action: {
                Task { await signIn() }
            }
            InlineMessage(text: runner.message, color: theme.colors.danger)
        }
    }

    private var capsuleStyle: ProviderCapsule<AppleLogo>.Style {
        switch style {
        case .black: return .filled(background: tint ?? .black, foreground: .white)
        case .white: return .filled(background: .white, foreground: .black)
        case .outline: return .outline(tint ?? theme.colors.onBackground)
        }
    }

    private func signIn() async {
        let succeeded = await runner.run {
            do {
                let credential = try await KitoAppleSignIn.signIn(scopes: scopes)
                return try await onCredential(credential)
            } catch let error as KitoAuthError {
                if !error.isCancellation { onError?(error) }
                throw error
            }
        }
        if succeeded {
            try? await Task.sleep(for: .seconds(1.4))
            runner.reset()
        }
    }
}

/// The Apple logo, from SF Symbols so it tracks Dynamic Type.
struct AppleLogo: View {
    var body: some View {
        Image(systemName: "apple.logo").font(.system(size: 18, weight: .semibold)).offset(y: -1)
    }
}

/// A provider button: capsule with a logo and title that morphs through loading and success.
struct ProviderCapsule<Logo: View>: View {
    enum Style {
        case filled(background: Color, foreground: Color)
        case outline(Color)
    }

    let title: String
    let style: Style
    var phase: MorphPhase = .idle
    var shakes = 0
    @ViewBuilder let logo: () -> Logo
    let action: () -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let height: CGFloat = 54

    private var background: Color {
        switch phase {
        case .success: return theme.colors.success
        case .failure: return theme.colors.danger
        default:
            if case .filled(let background, _) = style { return background }
            return .clear
        }
    }

    private var foreground: Color {
        if phase == .success || phase == .failure { return .white }
        switch style {
        case .filled(_, let foreground): return foreground
        case .outline(let color): return color
        }
    }

    private var border: Color {
        switch style {
        case .outline(let color): return phase == .idle || phase == .loading ? color.opacity(0.9) : .clear
        case .filled(let background, _): return background == .white ? Color.black.opacity(0.12) : .clear
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
                    Capsule().fill(background)
                    Capsule().strokeBorder(border, lineWidth: 1.5)
                    switch phase {
                    case .idle, .failure:
                        HStack(spacing: theme.spacing.sm) {
                            logo()
                            Text(title).font(theme.typography.button).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    case .loading:
                        ProgressView().tint(foreground).transition(.opacity)
                    case .success:
                        CheckmarkShape()
                            .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                            .environment(\.layoutDirection, .leftToRight) // a tick never mirrors
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .foregroundStyle(foreground)
                .frame(width: phase.isCollapsed ? height : proxy.size.width, height: height)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(isFilled ? 0.14 : 0), radius: 10, y: 5)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .animation(.authSpring(reduceMotion, bounce: 0.35), value: phase)
        }
        .frame(height: height)
        .authShake(shakes, reduceMotion: reduceMotion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(phase == .loading ? "In progress" : phase == .success ? "Done" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if phase == .idle || phase == .failure { action() } }
    }

    private var isFilled: Bool {
        if case .filled = style { return true }
        return false
    }
}
