//
//  KitoPasskeys.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import AuthenticationServices
import KitoCore
import SwiftUI

/// A new passkey to send to your server for storage.
public struct KitoPasskeyRegistration: Equatable, Sendable {
    public let credentialID: Data
    public let attestationObject: Data?
    public let clientDataJSON: Data
}

/// Proof that a person holds a passkey, to send to your server for verification.
public struct KitoPasskeyAssertion: Equatable, Sendable {
    public let credentialID: Data
    /// The user handle you registered the passkey with.
    public let userID: Data
    public let signature: Data
    public let authenticatorData: Data
    public let clientDataJSON: Data
}

/// Registers and uses passkeys for one relying party (your domain). Your server supplies
/// each challenge and verifies each result.
///
/// ```swift
/// let passkeys = KitoPasskeys(relyingParty: "example.com")
/// let assertion = try await passkeys.signIn(challenge: try await api.passkeyChallenge())
/// ```
///
/// Needs the `webcredentials:example.com` Associated Domain and an apple-app-site-association
/// file on that domain. Without them the system refuses, and this throws
/// `KitoAuthError.passkeysNotConfigured(domain:)` with a message saying what to add.
public struct KitoPasskeys: Sendable {
    public let relyingParty: String

    public init(relyingParty: String) {
        self.relyingParty = relyingParty
    }

    /// Creates a passkey. `userID` is your stable user handle (not the email); `userName`
    /// is what the password manager shows, usually the email.
    @MainActor
    public func register(challenge: Data, userID: Data, userName: String) async throws -> KitoPasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
        do {
            let authorization = try await AuthorizationSession.perform([request])
            guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
                throw KitoAuthError.failed(message: "The passkey couldn’t be created.")
            }
            return KitoPasskeyRegistration(credentialID: credential.credentialID,
                                           attestationObject: credential.rawAttestationObject,
                                           clientDataJSON: credential.rawClientDataJSON)
        } catch {
            throw AuthorizationSession.map(error, relyingParty: relyingParty)
        }
    }

    /// Signs in with a passkey. Pass `allowedCredentialIDs` to limit the choice to one account;
    /// leave it empty to let the person pick. `preferImmediatelyAvailable` fails fast (with
    /// `.cancelled`) instead of offering a QR code when no passkey is on this device.
    @MainActor
    public func signIn(challenge: Data, allowedCredentialIDs: [Data] = [],
                       preferImmediatelyAvailable: Bool = false) async throws -> KitoPasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = allowedCredentialIDs.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        do {
            let authorization = try await AuthorizationSession.perform([request], preferImmediatelyAvailable: preferImmediatelyAvailable)
            guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
                throw KitoAuthError.failed(message: "The passkey couldn’t be read.")
            }
            return KitoPasskeyAssertion(credentialID: credential.credentialID, userID: credential.userID,
                                        signature: credential.signature, authenticatorData: credential.rawAuthenticatorData,
                                        clientDataJSON: credential.rawClientDataJSON)
        } catch {
            throw AuthorizationSession.map(error, relyingParty: relyingParty)
        }
    }

    /// A random 32-byte challenge, for previews and local testing only. Real challenges must
    /// come from your server.
    public static func sampleChallenge() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// A capsule passkey button. It morphs into a spinner while `action` runs, a tick on success,
/// and shakes with a friendly message on failure (including a missing Associated Domain).
///
/// ```swift
/// KitoPasskeyButton {
///     let assertion = try await passkeys.signIn(challenge: try await api.challenge())
///     return try await api.verify(assertion) ? .success : .failure(message: "Passkey not recognised")
/// }
/// ```
public struct KitoPasskeyButton: View {
    public enum Mode: Sendable { case signIn, create }

    let mode: Mode
    var tint: Color?
    let action: () async throws -> KitoAuthResult

    @Environment(\.kitoTheme) private var theme
    @State private var runner = MorphRunner()

    public init(_ mode: Mode = .signIn, tint: Color? = nil, action: @escaping () async throws -> KitoAuthResult) {
        self.mode = mode
        self.tint = tint
        self.action = action
    }

    private var palette: AuthPalette { AuthPalette(theme: theme, tint: tint) }
    private var title: String { mode == .signIn ? "Sign in with a passkey" : "Create a passkey" }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            ProviderCapsule(title: title, style: .filled(background: palette.accent, foreground: palette.onAccent),
                            phase: runner.phase, shakes: runner.shakes) {
                Image(systemName: mode == .signIn ? "person.badge.key.fill" : "key.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            } action: {
                Task {
                    if await runner.run(action) {
                        try? await Task.sleep(for: .seconds(1.4))
                        runner.reset()
                    }
                }
            }
            InlineMessage(text: runner.message, color: theme.colors.danger)
                .font(theme.typography.caption)
        }
    }
}
