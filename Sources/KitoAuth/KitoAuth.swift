//
//  KitoAuth.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// What your server said. Return `.success` to play the success animation, or
/// `.failure(message:)` to shake and show the message inline.
public enum KitoAuthResult: Equatable, Sendable {
    case success
    case failure(message: String)

    /// A failure with the package's default wording.
    public static var failed: KitoAuthResult { .failure(message: "Something went wrong. Please try again.") }
}

/// Errors thrown by the Apple, passkey and biometric helpers. Each has a message you can show.
public enum KitoAuthError: Error, Equatable, LocalizedError, Sendable {
    /// The person dismissed the sheet. Views reset quietly instead of showing an error.
    case cancelled
    /// Passkeys need an `webcredentials:` Associated Domain and an apple-app-site-association file.
    case passkeysNotConfigured(domain: String)
    /// No window to present the system sheet from.
    case noPresentationAnchor
    /// Face ID or Touch ID is unavailable or not enrolled.
    case biometricsUnavailable
    /// The system returned something unexpected.
    case failed(message: String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Cancelled."
        case .passkeysNotConfigured(let domain):
            return "Passkeys aren’t set up for \(domain) yet. Add the webcredentials:\(domain) Associated Domain and host an apple-app-site-association file."
        case .noPresentationAnchor:
            return "There’s no window to show the sign-in sheet from."
        case .biometricsUnavailable:
            return "Face ID and Touch ID aren’t available on this device."
        case .failed(let message):
            return message
        }
    }

    /// True when the person backed out, so no error should be shown.
    public var isCancellation: Bool { self == .cancelled }
}

extension KitoAuthResult {
    /// Runs a server call, turning a throw into a failure with the error's message.
    /// Returns nil when the person cancelled a system sheet.
    static func catching(_ work: () async throws -> KitoAuthResult) async -> KitoAuthResult? {
        do {
            return try await work()
        } catch let error as KitoAuthError {
            if error.isCancellation { return nil }
            return .failure(message: error.localizedDescription)
        } catch is CancellationError {
            return nil
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }
}
