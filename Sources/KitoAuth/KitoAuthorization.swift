//
//  KitoAuthorization.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import AuthenticationServices
import UIKit

/// Runs one `ASAuthorizationController` request and hands back its credential via async/await.
@MainActor
final class AuthorizationSession: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?
    private var anchor: ASPresentationAnchor?

    /// Keeps sessions alive until the system calls back.
    private static var active: Set<AuthorizationSession> = []

    static func perform(_ requests: [ASAuthorizationRequest], preferImmediatelyAvailable: Bool = false) async throws -> ASAuthorization {
        guard let window = keyWindow() else { throw KitoAuthError.noPresentationAnchor }
        let session = AuthorizationSession()
        session.anchor = window
        active.insert(session)
        defer { active.remove(session) }
        return try await session.run(requests, preferImmediatelyAvailable: preferImmediatelyAvailable)
    }

    private func run(_ requests: [ASAuthorizationRequest], preferImmediatelyAvailable: Bool) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            if preferImmediatelyAvailable {
                controller.performRequests(options: .preferImmediatelyAvailableCredentials)
            } else {
                controller.performRequests()
            }
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor ?? ASPresentationAnchor() }
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.filter { $0.activationState == .foregroundActive }
        for scene in foreground + scenes {
            if let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first { return window }
        }
        return nil
    }

    /// Maps system errors to `KitoAuthError`, spotting a missing Associated Domain for passkeys.
    static func map(_ error: Error, relyingParty: String? = nil) -> KitoAuthError {
        if let error = error as? KitoAuthError { return error }
        let nsError = error as NSError
        let text = [nsError.localizedDescription, nsError.localizedFailureReason ?? "",
                    (nsError.userInfo[NSDebugDescriptionErrorKey] as? String) ?? ""].joined(separator: " ").lowercased()
        if let relyingParty, text.contains("not associated") || text.contains("associated domain") || text.contains("webcredentials") {
            return .passkeysNotConfigured(domain: relyingParty)
        }
        if nsError.domain == ASAuthorizationError.errorDomain, let code = ASAuthorizationError.Code(rawValue: nsError.code) {
            switch code {
            case .canceled:
                return .cancelled
            case .failed, .invalidResponse, .notHandled, .notInteractive:
                if let relyingParty, code == .failed { return .passkeysNotConfigured(domain: relyingParty) }
                return .failed(message: "Sign-in didn’t complete. Please try again.")
            case .unknown:
                return .failed(message: relyingParty == nil
                               ? "Sign in with Apple isn’t available. Check you’re signed in to an Apple Account and the capability is enabled."
                               : "Passkeys aren’t available right now.")
            default:
                return .failed(message: nsError.localizedDescription)
            }
        }
        return .failed(message: nsError.localizedDescription)
    }
}
